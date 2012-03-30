use strict;
use warnings;
use autodie ':all';
use File::chdir;

my $pan = './gitpan';

mkdir $pan, 0755;

{
  local $CWD = $pan;
  system qw(git init --bare);
  system qw(git config gc.auto 0);
}
