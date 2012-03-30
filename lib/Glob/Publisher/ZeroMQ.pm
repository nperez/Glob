package Glob::Publisher::ZeroMQ;

use Moose;
use JSON;
use namespace::autoclean;

has socket => (
    isa      => 'ZeroMQ::Socket',
    required => 1,
    handles  => ['send'],
);

method publish ($o) {
    $self->send(encode_json $o);
}

with 'Glob::Publisher';

__PACKAGE__->meta->make_immutable;

1;
