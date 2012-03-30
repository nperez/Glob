use strict;
use warnings;
use Path::Class;
use Path::Class::Rule;
use File::chdir;
use List::Gather;
use File::Temp 'tempdir';
use Cond::Expr;
use Archive::Zip 'AZ_OK';
use File::Spec::Functions 'splitdir';
use Try::Tiny;
use CPAN::DistnameInfo;
use feature 'say';
use JSON;
use ZeroMQ ':all';
use Parallel::Prefork;
use Proc::Fork;
use Data::Dump 'pp';
use POSIX 'SIGTERM';
use IPC::System::Simple 'capturex';
use File::Spec::Functions 'splitdir', 'splitpath';

#for i in $(cd /srv/backpan/CPAN; find authors -type f |egrep -v '\.(readme|meta)$' |sort |perl -ne'last if $_ eq qq[authors/id/F/FA/FAYLAND/Padre-Plugin-CPAN-0.03.tar.gz\n]}{print $_ while $_ = <>'); do echo $i; done |head -n10

my $backpan  = dir('/home/nicholas/mnt/backpan/');
my $pan      = dir('./gitpan')->absolute;
my $ipc_path = 'ipc:///tmp/backpan-jobs';

my %existing_refs = map { ($_ => 1) } gather {
    local $CWD = $pan;
    open my $fh, '-|', qw(git show-ref) or die $!;
    while (my $line = <$fh>) {
        chomp $line;
        take( (split /\s+/, $line, 2)[1] =~ s{refs/heads/}{}r );
    }
    unless (close $fh) {
        die $! unless ($? >> 8) == 1; # 1 - no refs
    }
};

run_watcher();

sub run_watcher {
    my $watcher_pid = $$;

    run_fork {
        child {
            try {
                $0 = 'walker';
                run_walker();
            }
            catch {
                die "walked exited: $_";
            }
            finally {
                #kill SIGTERM, $watcher_pid;
            };

            exit 0;
        }
        parent {
            $0 = 'watcher';

            my $pm = Parallel::Prefork->new({
                max_workers => 16,
            });

            while ($pm->signal_received ne 'TERM') {
                $pm->start(sub {
                    warn "spawning new worker";
                    try {
                        $0 = 'unpacker';
                        run_unpacker();
                    }
                    catch {
                        die "worker exited abnormally: $_";
                    };
                });
            }

            $pm->wait_all_children;
            warn "all done";
            exit 0;
        }
    };
}

sub run_walker {
    my $dist_rule = Path::Class::Rule->new->file->iname(
        '*.tar', qr'\.tar[._-]gz$', '*.tgz', '*.tar.bz2', '*.tbz', '*.tar.Z', '*.zip',
    );

    my $next = $dist_rule->iter($backpan->subdir('authors'), {
        follow_symlinks =>  0,
        depthfirst      => -1,
    });

    my $ctx = ZeroMQ::Context->new;
    my $pushsock = $ctx->socket(ZMQ_PUSH);
    $pushsock->bind($ipc_path);
    $pushsock->setsockopt(ZMQ_HWM, 32);

    warn "walking dists";
    while (my $abs_file = $next->()) {
        my $cpan_file = $abs_file->relative($backpan);
        my $dist = CPAN::DistnameInfo->new($cpan_file);
        my $normalised_distname = join '/' => map { $dist->$_ } qw(cpanid filename);

        next if exists $existing_refs{ $normalised_distname };
        $pushsock->send(encode_json {
            action => 'store_dist',
            dist   => {
                cpan_file       => $cpan_file->stringify,
                local_file      => $backpan->file($cpan_file)->stringify,
                normalised_name => $normalised_distname,
            },
        });
    }

    warn "DONE!";
}

sub run_unpacker {
    my $ctx = ZeroMQ::Context->new;
    my $pullsock = $ctx->socket(ZMQ_PULL);
    $pullsock->connect($ipc_path);
    $pullsock->setsockopt(ZMQ_HWM, 4);

    while (1) {
        my $payload = decode_json $pullsock->recv->data;
        cond
            ($payload->{action} eq 'store_dist') { gitify($payload->{dist}) }
            otherwise {
                die "unknown action in " . pp $payload;
            };
        1;
    }
}

sub gitify {
    my ($dist) = @_;

    my $work = tempdir(CLEANUP => 1);
    {
        local $CWD = $work;

        try {
            my $top = extract($dist->{local_file});
            capturex qw(find -type d -exec chmod u+rx {} ;);
            capturex qw(find -type f -exec chmod u+r {} ;);

            local $CWD = dir($top)->absolute($CWD);
            capturex qw(git init);
            capturex qw(git config gc.auto 0);
            capturex qw(git symbolic-ref HEAD),
                join '/' => 'refs', 'heads', $dist->{normalised_name};

            capturex qw(git add .);
            capturex qw(git commit -m), $dist->{normalised_name};

            capturex qw(git push -q), $pan,
                join '/' => qw(refs heads), $dist->{normalised_name};
            ();
        }
        catch {
            warn sprintf "skipping %s: %s", $dist->{cpan_file}, $_;
        };
    }

    try { system('rm', '-rf', $work) if $work };
}

sub extract {
  my ($file) = @_;
  return extract_zip(@_) if $file =~ /\.zip$/i;
  return extract_tar(@_);
}

sub extract_tar {
  my ($file) = @_;

  my $comp = cond
    ($file =~ /\.(?:z|tgz|\.tar[._-]gz|)$/i) { 'z' }
    ($file =~ /\.(?:bz2|tbz)$/i)             { 'j' }
    otherwise                                { ''  };

  open my $fh, '-|', 'tar', "tf${comp}", $file or die $!;
  chomp(my @files = <$fh>);
  close $fh or die "$file: tar exited with " . ($? >> 8);

  die "$file is empty" unless @files;

  check_naughtyness(\@files)
    or die "$file is naughty";

  open $fh, '-|', 'tar', "xf${comp}", $file or die $!;
  close $fh or die "$file: tar exited with " . ($? >> 8);

  my @dirs = splitpath $files[0];
  return +(splitdir(!length $dirs[1] ? $dirs[2] : $dirs[1]))[0];
}

sub extract_zip {
  my ($file) = @_;

  my $z = Archive::Zip->new;
  die "failed to read $file"
    unless $z->read( $file ) == AZ_OK;

  my @files = map { $_->fileName } $z->members;
  die "$file is empty" unless @files;

  check_naughtyness(\@files)
    or die "$file is naughty";

  $z->extractTree;

  return +(sort { length $a <=> length $b } @files)[0];
}

sub check_naughtyness {
  my ($files) = @_;

  my ($first_dir) = splitdir($files->[0]);
  return 0 if grep { !/^\Q$first_dir\E/ } @{ $files };
  return 0 if grep { m{^(?:/|(?:\./)*\.\./)} } @{ $files };
  return 1;
}
