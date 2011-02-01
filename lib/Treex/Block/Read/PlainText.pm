package Treex::Block::Read::PlainText;
use Moose;
use Treex::Moose;
extends 'Treex::Block::Read::BasePlainReader';
with 'Treex::Core::DocumentReader';

sub next_document {
    my ($self) = @_;
    my $text = $self->next_document_text();
    return if !defined $text;
    
    my $document = Treex::Core::Document->new();
    $document->set_attr( $self->selector . $self->language . ' text', $text );
    return $document;
}

1;
