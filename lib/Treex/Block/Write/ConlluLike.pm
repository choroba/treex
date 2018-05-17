package Treex::Block::Write::ConlluLike;

use Moose;
use Treex::Core::Common;

extends 'Treex::Block::Write::BaseTextWriter';

Readonly my $NOT_SET   => "_";    # CoNLL-ST format: undefined value

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
    my $t_node = shift;
    return grep { $_->get_bundle->id eq $t_node->get_bundle->id } @_;
}

sub get_tord2aord_mapping {
    my @nodes = @_;

    my %tord2aord;
    $tord2aord{0} = 0;
    my %aord_dict;
    my $last = 0;
    my $last_part = 0;
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

    return \%tord2aord;
}

sub ord_in_ords {
    my ($ord, $ords) = @_;

    my @matched = grep { $_ eq $ord } split /\|/, $ords;
    return scalar(@matched);
}

# MAIN
sub process_ttree {
    my ( $self, $t_root ) = @_;

    # Get all needed informations for each node
    my @nodes = $t_root->get_descendants( { ordered => 1 } );
    
    # First, let's establish t_ord to a_ord mapping
    my $tord2aord = get_tord2aord_mapping(@nodes);
    
    # Next, let's compute the info
    my $sent_id = substr $t_root->id(), 2;
    my $sent_text = $t_root->get_zone->sentence // '';
    # my @data = sort {$a->{aord} <=> $b->{aord}} map { get_node_info($_, $tord2aord) } @nodes;
    # t-nodes
    my %data = map { $_->{aord} => $_  } map { get_node_info($_, $tord2aord) } @nodes;
    # aux nodes
    foreach my $a_node ($t_root->get_zone->get_atree->get_descendants) {
        unless ($data{$a_node->ord}) {
            my $eparents = join '|',
                map { $data{$_}->{aord} }
                grep { ord_in_ords($a_node->ord, $data{$_}->{aux_ords}) }
                sort {$a <=> $b}
                keys %data;
            $data{$a_node->ord} = {
                aord => $a_node->ord,
                form => $a_node->form,
                lemma => $a_node->lemma,
                eparents => $eparents,
                # rest not set for auxes
                aux_ords => $NOT_SET,
                coref_ords => $NOT_SET,
                formeme => $NOT_SET,
                head => $NOT_SET,
                functor => $NOT_SET,
            }
        }
    }
    my @lines = map { $data{$_} } sort {$a <=> $b} keys %data;

    # print the results
    print {$self->_file_handle} "# sent_id = $sent_id\n";
    print {$self->_file_handle} "# text = $sent_text\n";
    foreach my $line (@lines) {
        $self->_print_st($line);
    }
    print { $self->_file_handle } ("\n");
    return 1;
}

# Retrieves all the information needed for the conversion of each node and
# stores it as a hash.
sub get_node_info {

    my ($t_node, $tord2aord) = @_;
    my %info;

    $info{aord}    = $tord2aord->{$t_node->ord};
    $info{head}     = $t_node->get_parent() ? $tord2aord->{$t_node->get_parent()->ord} : 0;
    my @eparents = $t_node->get_eparents({ ordered => 1, or_topological => 1 });
    $info{eparents} = @eparents ? join '|', map { $tord2aord->{$_->ord} } @eparents : $NOT_SET;
    
    $info{lemma}   = $t_node->t_lemma;
    $info{formeme} = $t_node->formeme;
    $info{functor} = $t_node->functor ? $t_node->functor : $NOT_SET;

    #my $a_node = get_lex_anode_in_same_sentence($t_node);
    #$info{lex_ord} = $a_node ? $a_node->ord : $NOT_SET;
    
    # $info{form}   = join '_', map {$_->form} $t_node->get_anodes({ ordered => 1 });
    $info{form}   = $t_node->get_lex_anode() ? $t_node->get_lex_anode()->form : $NOT_SET;

    my @aux_anodes = grep_this_sent($t_node, $t_node->get_aux_anodes( { ordered => 1 } ));
    $info{aux_ords} = @aux_anodes ? join '|', map { $_->ord } @aux_anodes : $NOT_SET;

    my @coref_tnodes = grep_this_sent($t_node, $t_node->get_coref_nodes( { ordered => 1 } ));
    $info{coref_ords}  = @coref_tnodes ? join '|', map { $tord2aord->{$_->ord} } @coref_tnodes : $NOT_SET;

    return \%info;
}

# Prints a data line in the pseudo-CoNLL format:
sub _print_st {
    my ( $self, $line )  = @_;

    print { $self->_file_handle } (
        join(
            "\t",
            (
                # id
                $line->{aord},
                # form
                $line->{form},
                # lemma
                $line->{lemma}, 
                # upos
                $line->{aux_ords},
                # xpos
                $line->{coref_ords},
                # feats
                $line->{formeme},
                # head
                $line->{head},
                # deprel
                $line->{functor},
                # deps
                $line->{eparents},
                # misc
                )
            )
    );
    print { $self->_file_handle } ("\n");
    return;
}

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

=head1 AUTHOR

Ondřej Dušek <odusek@ufal.mff.cuni.cz>

Rudolf Rosa <rosa@ufal.mff.cuni.cz>

=head1 COPYRIGHT AND LICENSE

Copyright © 2018 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
