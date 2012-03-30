package Glib::Unpacker;
use Moose;

use JSON;
use Cond::Expr;
use ZeroMQ;
use Data::Dump 'pp';

use Glob::Types(':all');

with qw/MooseX::Runnable MooseX::Getopt/;

has ipc_path => (
    is => 'ro',
    isa => IPCPath,
    required => 1,
    documentation => 'This is the IPC URL required for ZeroMQ',
);

has gitter => (
    is => 'ro',
    traits => ['NoGetopt'],
    isa => 'Glob::Git',
    required => 1,
    handles => [qw/
        gitify
    /],
);

sub run {
    my $ctx = ZeroMQ::Context->new;
    my $pullsock = $ctx->socket(ZMQ_PULL);
    $pullsock->connect($self->ipc_path);
    $pullsock->setsockopt(ZMQ_HWM, 4);

    while (1) {
        my $payload = decode_json $pullsock->recv->data;
        cond
            ($payload->{action} eq 'store_dist') { $self->gitify($payload->{dist}) }
            otherwise {
                die "unknown action in " . pp $payload;
            };
        1;
    }
}
