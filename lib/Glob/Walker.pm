package Glob::Walker;

use Moose;
use syntax 'method';
use aliased 'Path::Class::Rule';
use aliased 'CPAN::DistnameInfo';
use MooseX::Types::Path::Class 'Dir';
use MooseX::Types::Moose 'CodeRef';
use Glob::Types 'Publisher';
use namespace::autoclean;

has publisher => (
    isa      => Publisher,
    required => 1,
    handles  => {
        publish_dist => 'publish',
    },
);

has skip_predicate => (
    traits  => ['Code'],
    isa     => CodeRef,
    default => sub { sub { 0 } },
    handles => {
        should_skip => 'execute',
    },
);

has dist_dir => (
    is       => 'ro',
    isa      => Dir,
    required => 1,
    handles  => {
        absolute_dist_file => 'file',
    },
);

has dist_rule => (
    is       => 'ro',
    isa      => 'Path::Class::Rule',
    required => 1,
    builder  => '_build_dist_rule',
);

method _build_dist_rule {
    return Rule->new->file->iname(
        '*.tar', qr'\.tar[._-]gz$', '*.tgz', '*.tar.bz2', '*.tbz', '*.tar.Z', '*.zip',
    );
}

method dist_iterator {
    return $self->dist_rule->iter($self->dist_dir, {
        follow_symlinks =>  0,
        depthfirst      => -1,
    });
}

method run_walker {
    warn "walking dists";

    my $next = $self->dist_iterator;

    while (my $abs_file = $next->()) {
        my $cpan_file = $abs_file->relative( $self->dist_dir );
        my $dist = DistnameInfo->new($cpan_file);
        my $normalised_distname = join '/' => map { $dist->$_ } qw(cpanid filename);

        next if $self->should_skip($normalised_distname);

        $self->publish_dist({
            action => 'store_dist',
            dist   => {
                cpan_file       => $cpan_file->stringify,
                local_file      => $self->absolute_dist_file($cpan_file)->stringify,
                normalised_name => $normalised_distname,
            },
        });
    }

    warn "DONE!";
}
