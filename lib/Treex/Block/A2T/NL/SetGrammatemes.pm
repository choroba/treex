package Treex::Block::A2T::NL::SetGrammatemes;

use Moose;
use Treex::Core::Common;
use Treex::Tool::Lexicon::NL::ErgativeVerbs;

extends 'Treex::Block::A2T::SetGrammatemes';

# TODO: add all possible verbal group signatures (or some equivalent rules)
my %SIG2GRAM = (

    # simple (synthetic) forms: present, past, participles, infinitive
    'LEX-finpres'  => { 'diathesis' => 'act', 'tense' => 'sim', 'deontmod' => 'decl', 'verbmod' => 'ind' },
    'LEX-finpast'  => { 'diathesis' => 'act', 'tense' => 'ant', 'deontmod' => 'decl', 'verbmod' => 'ind' },
    'LEX-partpres' => { 'diathesis' => 'act', 'tense' => 'sim', 'deontmod' => 'decl', 'verbmod' => 'ind' },
    'LEX-partpast' => { 'diathesis' => 'pas', 'tense' => 'ant', 'deontmod' => 'decl', 'verbmod' => 'ind' },
    'LEX-inf'      => { 'diathesis' => 'act', 'tense' => 'nil', 'deontmod' => 'decl', 'verbmod' => 'nil' },

    # present/past with modals
    'moeten-finpres+LEX-inf' => { 'diathesis' => 'act', 'tense' => 'sim', 'deontmod' => 'hrt',  'verbmod' => 'ind' },
    'moeten-finpast+LEX-inf' => { 'diathesis' => 'act', 'tense' => 'ant', 'deontmod' => 'hrt',  'verbmod' => 'ind' },
    'kunnen-finpres+LEX-inf' => { 'diathesis' => 'act', 'tense' => 'sim', 'deontmod' => 'poss', 'verbmod' => 'ind' },
    'kunnen-finpast+LEX-inf' => { 'diathesis' => 'act', 'tense' => 'ant', 'deontmod' => 'poss', 'verbmod' => 'ind' },
    'mogen-finpres+LEX-inf'  => { 'diathesis' => 'act', 'tense' => 'sim', 'deontmod' => 'perm', 'verbmod' => 'ind' },
    'mogen-finpast+LEX-inf'  => { 'diathesis' => 'act', 'tense' => 'ant', 'deontmod' => 'perm', 'verbmod' => 'ind' },
    'willen-finpres+LEX-inf' => { 'diathesis' => 'act', 'tense' => 'sim', 'deontmod' => 'vol',  'verbmod' => 'ind' },
    'willen-finpast+LEX-inf' => { 'diathesis' => 'act', 'tense' => 'ant', 'deontmod' => 'vol',  'verbmod' => 'ind' },

    # future / conditional active
    'zullen-finpres+LEX-inf' => { 'diathesis' => 'act', 'tense' => 'post', 'deontmod' => 'decl', 'verbmod' => 'ind' },
    'zullen-finpast+LEX-inf' => { 'diathesis' => 'act', 'tense' => 'sim',  'deontmod' => 'decl', 'verbmod' => 'cdn' },

    # past (heb gemaakt, had gemaakt)
    'hebben-finpres+LEX-partpast' => { 'diathesis' => 'act', 'tense' => 'ant', 'deontmod' => 'decl', 'verbmod' => 'ind' },
    'hebben-finpast+LEX-partpast' => { 'diathesis' => 'act', 'tense' => 'ant', 'deontmod' => 'decl', 'verbmod' => 'ind' },

    # passive
    'worden-finpres+LEX-partpast' => { 'diathesis' => 'pas', 'tense' => 'sim', 'deontmod' => 'decl', 'verbmod' => 'ind' },
    'worden-finpast+LEX-partpast' => { 'diathesis' => 'pas', 'tense' => 'ant', 'deontmod' => 'decl', 'verbmod' => 'ind' },

    # future/conditional with modals
    'zullen-finpres+moeten-inf+LEX-inf' => { 'diathesis' => 'act', 'tense' => 'post', 'deontmod' => 'hrt',  'verbmod' => 'ind' },
    'zullen-finpres+willen-inf+LEX-inf' => { 'diathesis' => 'act', 'tense' => 'post', 'deontmod' => 'vol',  'verbmod' => 'ind' },
    'zullen-finpres+kunnen-inf+LEX-inf' => { 'diathesis' => 'act', 'tense' => 'post', 'deontmod' => 'poss', 'verbmod' => 'ind' },
    'zullen-finpres+mogen-inf+LEX-inf'  => { 'diathesis' => 'act', 'tense' => 'post', 'deontmod' => 'perm', 'verbmod' => 'ind' },
    'zullen-finpast+moeten-inf+LEX-inf' => { 'diathesis' => 'act', 'tense' => 'sim', 'deontmod' => 'hrt',  'verbmod' => 'cdn' },
    'zullen-finpast+willen-inf+LEX-inf' => { 'diathesis' => 'act', 'tense' => 'sim', 'deontmod' => 'vol',  'verbmod' => 'cdn' },
    'zullen-finpast+kunnen-inf+LEX-inf' => { 'diathesis' => 'act', 'tense' => 'sim', 'deontmod' => 'poss', 'verbmod' => 'cdn' },
    'zullen-finpast+mogen-inf+LEX-inf'  => { 'diathesis' => 'act', 'tense' => 'sim', 'deontmod' => 'perm', 'verbmod' => 'cdn' },
    
    # future/conditional with modals+passive
    'zullen-finpres+moeten-inf+worden-inf+LEX-partpast'  => { 'diathesis' => 'pas', 'tense' => 'post', 'deontmod' => 'hrt',  'verbmod' => 'ind' },
    'zullen-finpres+willen-inf+worden-inf+LEX-partpast'  => { 'diathesis' => 'pas', 'tense' => 'post', 'deontmod' => 'vol',  'verbmod' => 'ind' },
    'zullen-finpres+kunnen-inf+worden-inf+LEX-partpast'  => { 'diathesis' => 'pas', 'tense' => 'post', 'deontmod' => 'poss', 'verbmod' => 'ind' },
    'zullen-finpres+mogen-inf+worden-inf+LEX-partpast'  =>  { 'diathesis' => 'pas', 'tense' => 'post', 'deontmod' => 'perm', 'verbmod' => 'ind' },
    'zullen-finpast+moeten-inf+worden-inf+LEX-partpast'  => { 'diathesis' => 'pas', 'tense' => 'sim', 'deontmod' => 'hrt',  'verbmod' => 'cdn' },
    'zullen-finpast+willen-inf+worden-inf+LEX-partpast'  => { 'diathesis' => 'pas', 'tense' => 'sim', 'deontmod' => 'vol',  'verbmod' => 'cdn' },
    'zullen-finpast+kunnen-inf+worden-inf+LEX-partpast'  => { 'diathesis' => 'pas', 'tense' => 'sim', 'deontmod' => 'poss', 'verbmod' => 'cdn' },
    'zullen-finpast+mogen-inf+worden-inf+LEX-partpast'  =>  { 'diathesis' => 'pas', 'tense' => 'sim', 'deontmod' => 'perm', 'verbmod' => 'cdn' },

    # passive with modals
    'moeten-finpres+worden-inf+LEX-partpast' => { 'diathesis' => 'pas', 'tense' => 'sim', 'deontmod' => 'hrt',  'verbmod' => 'ind' },
    'moeten-finpast+worden-inf+LEX-partpast' => { 'diathesis' => 'pas', 'tense' => 'ant', 'deontmod' => 'hrt',  'verbmod' => 'ind' },
    'kunnen-finpres+worden-inf+LEX-partpast' => { 'diathesis' => 'pas', 'tense' => 'sim', 'deontmod' => 'poss', 'verbmod' => 'ind' },
    'kunnen-finpast+worden-inf+LEX-partpast' => { 'diathesis' => 'pas', 'tense' => 'ant', 'deontmod' => 'poss', 'verbmod' => 'ind' },
    'mogen-finpres+worden-inf+LEX-partpast'  => { 'diathesis' => 'pas', 'tense' => 'sim', 'deontmod' => 'perm', 'verbmod' => 'ind' },
    'mogen-finpast+worden-inf+LEX-partpast'  => { 'diathesis' => 'pas', 'tense' => 'ant', 'deontmod' => 'perm', 'verbmod' => 'ind' },
    'willen-finpres+worden-inf+LEX-partpast' => { 'diathesis' => 'pas', 'tense' => 'sim', 'deontmod' => 'vol',  'verbmod' => 'ind' },
    'willen-finpast+worden-inf+LEX-partpast' => { 'diathesis' => 'pas', 'tense' => 'ant', 'deontmod' => 'vol',  'verbmod' => 'ind' },

    # future / conditional passive
    'zullen-finpres+worden-inf+LEX-partpast' => { 'diathesis' => 'pas', 'tense' => 'post', 'deontmod' => 'decl', 'verbmod' => 'ind' },
    'zullen-finpast+worden-inf+LEX-partpast' => { 'diathesis' => 'pas', 'tense' => 'sim',  'deontmod' => 'decl', 'verbmod' => 'cdn' },
);

override 'set_verbal_grammatemes' => sub {
    my ( $self, $tnode, $anode ) = @_;

    my $sig = $self->get_verbal_group_signature( $tnode, $anode );
    my $gram = $SIG2GRAM{$sig};

    # distinguishing past tense and passive for "is/was + past participle"
    if ( $sig =~ 'zijn-(finpast|finpres)\+LEX-partpast' ) {

        # ergative verbs (can't build passive): past tense
        $gram = { 'tense' => 'ant', 'deontmod' => 'decl', 'verbmod' => 'ind' };
        if ( Treex::Tool::Lexicon::NL::ErgativeVerbs::is_ergative_verb( $tnode->t_lemma ) ) {
            $gram->{'diathesis'} = 'act';
        }

        # other: passive
        else {
            $gram->{'diathesis'} = 'pas';
        }
    }

    if ($gram) {
        while ( my ( $gram_name, $gram_val ) = each %$gram ) {
            $tnode->set_attr( 'gram/' . $gram_name, $gram_val );
        }
    }
    else {
        my $id = $tnode->id . ' -- ' . join(' ', map { lc $_->form } grep { $_->is_verb } $tnode->get_anodes( { ordered => 1 } ) );
        log_warn( "No grammatemes found for verbal group signature `$sig': $id");
    }
    return 1;
};

sub get_form_signature {
    my ( $self, $anode ) = @_;
    return $anode->get_iset('verbform') . $anode->get_iset('tense');
}

# returns de-lexicalized signature of all verb forms in the verbal group (to be mapped to grammatemes)
sub get_verbal_group_signature {
    my ( $self, $tnode, $lex_anode ) = @_;
    my @sig = ();
    foreach my $anode ( grep { $_->is_verb } $tnode->get_anodes( { ordered => 1 } ) ) {

        # de-lexicalize
        my $lemma = $anode == $lex_anode ? 'LEX' : $anode->lemma;

        # put finite verb first at all times (handle word order change in some embedded clauses)
        if ( $anode->match_iset( 'verbform' => 'fin' ) ) {
            unshift @sig, $lemma . '-' . $self->get_form_signature($anode);
        }
        else {
            push @sig, $lemma . '-' . $self->get_form_signature($anode);
        }
    }

    #log_info( join( ' ', map { $_->form } $tnode->get_anodes( { ordered => 1 } ) ) . ' -- ' . join( '+', @sig ) );
    return join( '+', @sig );
}

1;

__END__

=encoding utf-8

=head1 NAME

Treex::Block::A2T::NL::SetGrammatemes

=head1 DESCRIPTION

Dutch-specific settings for grammatemes values.

Currently, verbal grammatemes are set according to the shape of the verbal group.

=back

=head1 AUTHOR

Ondřej Dušek <odusek@ufal.mff.cuni.cz>

=head1 COPYRIGHT AND LICENSE

Copyright © 2014 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
