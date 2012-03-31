package Glob::Watcher;

use Moose;
use syntax 'method', 'function';
use Proc::Fork;
use MooseX::Types::Moose 'CodeRef';
use MooseX::Types::Common::Numeric 'PositiveInt';
use aliased 'Parallel::Runner';
use namespace::autoclean;

has max_unpacker_processes => (
    is       => 'ro',
    isa      => PositiveInt,
    required => 1,
    default  => 16,
);

has fork_manager => (
    is      => 'ro',
    isa     => Runner,
    lazy    => 1,
    builder => '_build_fork_manager',
    handles => {
        run_child         => 'run',
        running_children  => 'children',
        wait_for_children => 'finish',
    },
);

has workload => (
    is       => 'ro',
    isa      => CodeRef,
    required => 1,
);

method _build_fork_manager {
    my $runner = Runner->new( $self->max_unpacker_processes );
    $runner->reap_callback(fun ($status, $pid) {
        warn "worker $pid exited with $status";
        $self->run_many( $self->workload );
    });

    return $runner;
}

method BUILD {
    $self->fork_manager;
}

method run_many ($cb) {
    my $needed_children = $self->max_unpacker_processes - $self->running_children;

    $self->run_child($cb) for 1 .. $needed_children;
}

method run {
    my $watcher_pid = $$;
    $0 = 'watcher';

    $self->run_many(fun {
        warn "spawning new worker";
        try {
            $0 = $self->workload_name;
            $self->workload->();
        }
        catch {
            die "worker exited abnormally: $_";
        };
    });

    $self->wait_for_children;
    warn "all done";
}

__PACKAGE__->meta->make_immutable;

1;
