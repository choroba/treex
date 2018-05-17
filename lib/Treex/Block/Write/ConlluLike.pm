package Treex::Block::Write::ConlluLike;

use Moose;
use Treex::Core::Common;

extends 'Treex::Block::Write::BaseTextWriter';

Readonly my $NOT_SET   => "_";    # CoNLL-ST format: undefined value
Readonly my $NO_NUMBER => -1;     # CoNLL-ST format: undefined integer value
Readonly my $FILL      => "_";    # CoNLL-ST format: "fill predicate"
Readonly my $TAG_FEATS => {
    "SubPOS" => 1,
    "Gen"    => 2,
    "Num"    => 3,
    "Cas"    => 4,
    "PGe"    => 5,
    "PNu"    => 6,
    "Per"    => 7,
    "Ten"    => 8,
    "Gra"    => 9,
    "Neg"    => 10,
    "Voi"    => 11,
    "Var"    => 14
};    # tag positions and their meanings
Readonly my $TAG_NOT_SET => "-";    # tagset: undefined value

has '+language' => ( required => 1 );

has '+extension' => ( default => '.conll' );

sub get_lex_anode_in_same_sentence {
    my ($t_node) = @_;

    my $a_node = $t_node->get_lex_anode();

    if (defined $a_node && $a_node->get_bundle->id eq $t_node->get_bundle->id) {
        return $a_node;
    } else {
        return undef;
    }
}

sub grep_this_sent {
    #my $self = shift;
    my $t_node = shift;
    return grep { $_->get_bundle->id eq $t_node->get_bundle->id } @_;
}

# MAIN
sub process_ttree {
    my ( $self, $t_root ) = @_;

    # Get all needed informations for each node
    my @data;
    my @nodes = $t_root->get_descendants( { ordered => 1 } );
    
    # First, let's establish t_ord to a_ord mapping
    my %tord2aord;
    $tord2aord{0} = 0;
    my %aord_dict;
    my $last = 0;
    my $last_part = 0;
    my $bundle_id = $t_root->get_bundle->id;
    foreach my $t_node (@nodes) {
        my $gen = $t_node->is_generated;
        my $a_node = get_lex_anode_in_same_sentence($t_node);
        my $aord;
        if ($gen) {
            $last_part++;
            $aord = "$last.$last_part";
        } else {
            # checks
            if (!defined $a_node) {
                log_fatal($t_node->id . " not generated but has no lex anode!");
            }
            
            $aord = $a_node->ord;
            $last = $aord;
            $last_part = 0;            
        }
        $tord2aord{$t_node->ord} = $aord;
        
        # checks
        if ($aord_dict{$aord}) {
            log_fatal($t_node->id . " second reference to anode $aord!");
        } else {
            $aord_dict{$aord} = 1;
        }
    }
    
    # Next, let's compute the info
    foreach my $node (@nodes) {
        push( @data, get_node_info($node, \%tord2aord) );
    }

    # print the results
    # sentence id
    # my $a_root = $t_root->get_zone->get_atree();
    my $sent_id = $t_root->id();
    $sent_id =~ s/^a-//; 
    #$sent_id .= '/' . $tree->get_zone->get_label;
    print {$self->_file_handle} "# sent_id = $sent_id\n";
    # sentence text
    my $text = $t_root->get_zone->sentence;
    print {$self->_file_handle} "# text = $text\n" if defined $text;
    # nodes
    foreach my $line (@data) {
        $self->_print_st($line);
    }
    # sentence separator
    print { $self->_file_handle } ("\n");
    return 1;
}

# Retrieves all the information needed for the conversion of each node and
# stores it as a hash.
sub get_node_info {

    my ($t_node, $tord2aord) = @_;
    my %info;

    #$info{"ord"}   = $t_node->ord;
    $info{aord}    = $tord2aord->{$t_node->ord};
    # TODO or eparent?
    $info{head}    = $t_node->get_parent() ? $tord2aord->{$t_node->get_parent()->ord} : 0;
    
    $info{functor} = $t_node->functor ? $t_node->functor : $NOT_SET;
    $info{lemma}   = $t_node->t_lemma;
    $info{formeme} = $t_node->formeme;

    #if ($t_node->is_generated && $info{"lemma"} !~ /^#/ ) {
    #    $info{"lemma"}   = '#' . $info{"lemma"};
    #}

    my $a_node = get_lex_anode_in_same_sentence($t_node);
    $info{lex_ord} = $a_node ? $a_node->ord : $NOT_SET;

    #if ($a_node) {    # there is a corresponding node on the a-layer
    #   $info{"lex_ord"} = $a_node->ord;
        #$info{"tag"}  = $a_node->tag;
        #$info{"form"} = $a_node->form;
        #$info{"afun"} = $a_node->afun;
        #}
        #else {            # generated node
        #$info{"lex_ord"} = $NOT_SET;
        #$info{"tag"}  = $NOT_SET;
        #$info{"afun"} = $NOT_SET;
        #$info{"form"} = $info{"lemma"};
        #}

    # initialize aux-info
    #$info{"aux_ords"}  = "";
    #$info{"aux_forms"}  = "";
    #$info{"aux_lemmas"} = "";
    #$info{"aux_pos"}    = "";
    #$info{"aux_subpos"} = "";
    #$info{"aux_afuns"}  = "";

    # get all aux-info nodes
    my @aux_anodes = grep_this_sent($t_node, $t_node->get_aux_anodes( { ordered => 1 } ));
    $info{"aux_ords"} = @aux_anodes ? join '|', map { $_->ord } @aux_anodes : $NOT_SET;

    my @coref_tnodes = grep_this_sent($t_node, $t_node->get_coref_nodes( { ordered => 1 } ));
    $info{"coref_ords"}  = @coref_tnodes ? join '|', map { $tord2aord->{$_->ord} } @coref_tnodes : $NOT_SET;
    
    # $node->get_coref_gram_nodes()
    # special nodes -- vygenerovanej node odkazuje

    # $node->get_coref_text_nodes()
    # pronouns -- odkazuje se textem


    #$info{"aux_ords"}   = $info{"aux_ords"}   eq "" ? $NOT_SET : substr( $info{"aux_ords"},  1 );
    #$info{"aux_forms"}  = $info{"aux_forms"}  eq "" ? $NOT_SET : substr( $info{"aux_forms"},  1 );
    #$info{"aux_lemmas"} = $info{"aux_lemmas"} eq "" ? $NOT_SET : substr( $info{"aux_lemmas"}, 1 );
    #$info{"aux_pos"}    = $info{"aux_pos"}    eq "" ? $NOT_SET : substr( $info{"aux_pos"},    1 );
    #$info{"aux_subpos"} = $info{"aux_subpos"} eq "" ? $NOT_SET : substr( $info{"aux_subpos"}, 1 );
    #$info{"aux_afuns"}  = $info{"aux_afuns"}  eq "" ? $NOT_SET : substr( $info{"aux_afuns"},  1 );

    return \%info;
}

# Prints a data line in the pseudo-CoNLL-ST format:
#     ID, FORM, LEMMA, (nothing), PoS, (nothing), PoS Features, (nothing),
#     HEAD, (nothing), FUNCTOR, (nothing), Y, (nothing),
#     AFUN, AUX-FORMS, AUX-LEMMAS, AUX-POS, AUX-SUBPOS, AUX-AFUNS
sub _print_st {
    my ( $self, $line )  = @_;
    # my ( $pos,  $pfeat ) = $self->_analyze_tag( $line->{"tag"} );

    print { $self->_file_handle } (
        join(
            "\t",
            (
                $line->{aord},
                $line->{lex_ord},
                $line->{aux_ords},
                $line->{coref_ords},
                # $line->{"form"},
                $line->{"lemma"}, 
                $line->{"head"},
                $line->{"functor"},
                $line->{formeme},
                )
            )
    );
    print { $self->_file_handle } ("\n");
    return;
}

# Given a tag, returns the PoS and PoS-Feat values for Czech, just the tag and "_" for any other
# language; or double "_", given an unset tag value.
# sub _analyze_tag {
# 
#     my ( $self, $tag ) = @_;
# 
#     if ( $tag eq $NOT_SET ) {
#         return ( $NOT_SET, $NOT_SET );
#     }
#     if ( $self->language ne "cs" ) {
#         return ( $tag, $NOT_SET );
#     }
# 
#     my $pos = substr( $tag, 0, 1 );
#     my $pfeat = "";
# 
#     foreach my $feat ( keys %{$TAG_FEATS} ) {
#         my $idx = $TAG_FEATS->{$feat};
#         my $val = substr( $tag, $idx, 1 );
# 
#         if ( $val ne $TAG_NOT_SET ) {
#             $pfeat .= $pfeat eq "" ? "" : "|";
#             $pfeat .= $feat . "=" . $val;
#         }
#     }
#     return ( $pos, $pfeat );
# }

# Given a PDT-style morphological lemma, returns just the "lemma proper" part without comments, links, etc.
#sub lemma_proper {
#    my ($lemma) = @_;
#    $lemma =~ s/(_;|_:|_,|_\^|`).*$//;
#    return $lemma;
#}

1;

__END__

=encoding utf-8

=head1 NAME 

Treex::Block::Write::ConlluLike

=head1 DESCRIPTION

Based on Treex::Block::Write::ConllLike

Prints out all t-trees in a text format similar to CoNLL-U

=head1 PARAMETERS

=over

=item C<language>

This parameter is required.

=item C<to>

Optional: the name of the output file, STDOUT by default.

=item C<encoding>

Optional: the output encoding, C<utf8> by default.

=back

=head1 TODO

Parametrize, so that the true CoNLL output as well as this extended version is possible.

=head1 AUTHOR

Ondřej Dušek <odusek@ufal.mff.cuni.cz>

Rudolf Rosa <rosa@ufal.mff.cuni.cz>

=head1 COPYRIGHT AND LICENSE

Copyright © 2018 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
