package Treex::Block::Filter::CzEng::Common;
use Moose;
use Treex::Core::Common;
extends 'Treex::Core::Block';

sub add_feature {
    my ( $self, $bundle, $feature ) = @_;

    if ( not $bundle->get_zone('und') ) {
        my $zone = $bundle->create_zone('und');
        $zone->set_sentence('FILTER_OUTPUTS:');
    }

    $bundle->get_zone('und')->set_sentence( $bundle->get_zone('und')->sentence . " $feature" );
    return 1;
}

sub get_features {
    my ( $self, $bundle ) = @_;
    if ( !$bundle->get_zone('und') || !$bundle->get_zone('und')->sentence ) {
        return undef;
    }
    my ( undef, @features ) = split /\s+/, $bundle->get_zone('und')->sentence;
    return @features;
}

sub quantize {
    my ( $self, $precision, $value, $max_value ) = @_;
    my $bucket = $precision * int( $value / $precision );
    if (defined $max_value && $bucket > $max_value) {
        $bucket = $max_value;
    }
    return $bucket;
}

sub quantize_given_bounds {
    my ( $self, $value, @bounds ) = @_;
    my $bucket = "min";
    for my $bound ( @bounds ) {
        if ( $value < $bound ) {
            last;
        } else {
            $bucket = $bound;
        }
    }
    return $bucket;
}

1;

=over

=item Treex::Block::Filter::CzEng::Common

Common antecedent of filtering blocks.

=back

=cut

# Copyright 2011 Zdenek Zabokrtsky

# This file is distributed under the GNU General Public License v2. See $TMT_ROOT/README.
