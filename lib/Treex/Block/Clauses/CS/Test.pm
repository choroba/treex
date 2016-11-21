package Treex::Block::Clauses::CS::Test;
use Moose;
use Treex::Core::Common;
extends 'Treex::Core::Block';

sub process_start {
    my ($self) = @_;

    print "PROCESS START\n";
}

sub process_end {
    my ($self) = @_;

    print "PROCESS END\n";
}

1;
