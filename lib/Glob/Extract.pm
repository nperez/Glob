package Glob::Extract;
use Moose;
use Cond::Expr;
use Archive::Zip 'AZ_OK';
use File::Spec::Functions 'splitdir', 'splitpath';

sub extract {
  my ($self, $file) = @_;
  return _extract_zip(@_) if $file =~ /\.zip$/i;
  return _extract_tar(@_);
}

sub _extract_tar {
  my ($file) = @_;

  my $comp = cond
    ($file =~ /\.(?:z|tgz|\.tar[._-]gz|)$/i) { 'z' }
    ($file =~ /\.(?:bz2|tbz)$/i)             { 'j' }
    otherwise                                { ''  };

  open my $fh, '-|', 'tar', "tf${comp}", $file or die $!;
  chomp(my @files = <$fh>);
  close $fh or die "$file: tar exited with " . ($? >> 8);

  die "$file is empty" unless @files;

  _check_naughtyness(\@files)
    or die "$file is naughty";

  open $fh, '-|', 'tar', "xf${comp}", $file or die $!;
  close $fh or die "$file: tar exited with " . ($? >> 8);

  my @dirs = splitpath $files[0];
  return +(splitdir(!length $dirs[1] ? $dirs[2] : $dirs[1]))[0];
}

sub _extract_zip {
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

sub _check_naughtyness {
  my ($files) = @_;

  my ($first_dir) = splitdir($files->[0]);
  return 0 if grep { !/^\Q$first_dir\E/ } @{ $files };
  return 0 if grep { m{^(?:/|(?:\./)*\.\./)} } @{ $files };
  return 1;
}

__PACKAGE__->meta->make_immutable();

1;
