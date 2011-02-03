package Treex::Core::Zone;

# antecedent of DocZone and BundleZone

use Moose;
use Treex::Moose;
use MooseX::NonMoose;

#extends 'Treex::PML::Seq::Element';
extends 'Treex::PML::Struct';

has language => (is => 'rw');

has selector => (is => 'rw');

sub set_attr {
    my ($self, $attr_name, $attr_value) = @_;
    return $self->{$attr_name} = $attr_value;
}

sub get_attr {
    my ($self, $attr_name) = @_;
    return $self->{$attr_name};
}

sub get_label {
    my ($self) = @_;
    return $self->get_selector . $self->get_language;
}
1;
