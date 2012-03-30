package Glob::Git;
use Moose;
use IPC::System::Simple 'capturex';
use File::Temp 'tempdir';
use Try::Tiny;
use Path::Class;

use Glob::Types(':all');

has extractor => (
    is => 'ro',
    isa => 'Glob::Extract',
    required => 1,
    handles => [qw/
        extract
    /],
);

has glob_root => (
    is => 'ro',
    isa => GlobRoot,
    coerce => 1,
    required => 1,
);

sub gitify {
    my ($self, $dist) = @_;

    my $work = tempdir(CLEANUP => 1);
    {
        my $cwd = $work;

        try {
            my $top = $self->extract($dist->{local_file});
            capturex qw(find -type d -exec chmod u+rx {} ;);
            capturex qw(find -type f -exec chmod u+r {} ;);

            $cwd = dir($top)->absolute($cwd);
            capturex qw(git init);
            capturex qw(git config gc.auto 0);
            capturex qw(git symbolic-ref HEAD),
                join '/' => 'refs', 'heads', $dist->{normalised_name};

            capturex qw(git add .);
            capturex qw(git commit -m), $dist->{normalised_name};

            capturex qw(git push -q), $self->glob_root,
                join '/' => qw(refs heads), $dist->{normalised_name};
            ();
        }
        catch {
            warn sprintf "skipping %s: %s", $dist->{cpan_file}, $_;
        };
    }

    try { system('rm', '-rf', $work) if $work };
}
