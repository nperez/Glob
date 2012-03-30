package Glob::Types;
use Path::Class;
use MooseX::Types::Moose(':all');
use MooseX::Types -declare => [qw/
    GlobRoot
    Publisher
    IPCPath
/];

subtype GlobRoot,
    as class_type('Path::Class'),
    where { my $path = $_->absolute; qx(cd $path; git status 2>&1) !~ /fatal:.*/ };

coerce GlobRoot,
    from Str,
    via { dir($_) };

subtype IPCPath,
    as Str,
    where { m#ipc://.+# };

role_type Publisher, { class => 'Glob::Publisher' };

1;
