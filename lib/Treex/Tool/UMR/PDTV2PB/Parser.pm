package Treex::Tool::UMR::PDTV2PB::Parser;
use Moose;
use experimental qw( signatures );

use Marpa::R2;
use namespace::clean;

has dsl     => (is => 'ro', lazy => 1, builder => '_build_dsl');
has grammar => (is => 'ro', lazy => 1, builder => '_build_grammar');
has debug   => (is => 'ro', default => 0);


sub _build_dsl($) {
    return \<< '__DSL__'

    lexeme default = latm => 1

    :default           ::= action => [name,values]
    Rule               ::= Commands
    Commands           ::= Value | attr colon Value | Value MaybeComma Commands | Command | Command MaybeComma Commands
    MaybeComma         ::= comma
    MaybeComma         ::= 
    Value              ::= Relation | Concept | functor
    Command            ::= (exclam) No_args | (exclam) Args | If | DeleteRoot
    DeleteRoot         ::= (lpar) (exclam) delete comma functor (rpar)
    If                 ::= if (lpar) Conditions (rpar) (lpar) Commands (rpar) Else
    Else               ::= else (lpar) Commands (rpar) | else If | else (exclam) No_args
    Conditions         ::= Condition | Condition comma Conditions
    Condition          ::= Maybe_node attr colon Lemmas | functor colon Lemmas | Maybe_node attr colon functor
    Maybe_node         ::= node (dot)
    Maybe_node         ::= 
    Lemmas             ::= Lemma | Lemma comma Lemmas
    Lemma              ::= lemma | upper1 lemma
    Relation           ::= arg num
    Concept            ::= Cprefixes Csuffix | concept
    Csuffix            ::= csuffix | new dash csuffix
    Cprefixes          ::= cprefix dash Cprefixes | cprefix dash functor | cprefix dash functor dash | cprefix dash
    No_args            ::= delete | root | error | ok
    Args               ::= Set_modal_strength | Set_aspect | Set_polarity | Set_tlemma | Set_relation | Add
    Set_modal_strength ::= modal_strength (lpar) modal_strength_value (rpar)
    Set_aspect         ::= aspect (lpar) aspect_value (rpar)
    Set_polarity       ::= polarity (lpar) dash (rpar)
    Set_tlemma         ::= tlemma (lpar) Concept (rpar)
    Set_relation       ::= relation (lpar) Relation (rpar)
    Add                ::= add (lpar) node (dot) Args_list (rpar)
    Args_list           ::= Args | Args (comma) Args_list

    :discard             ~ whitespace
    whitespace           ~ [\s]+
    lpar                 ~ '('
    rpar                 ~ ')'
    arg                  ~ 'ARG'
    num                  ~ [0-9]
    cprefix              ~ [[:lower:]]+
    csuffix              ~ [0-9]+
    upper1               ~ [[:upper:]]
    lemma                ~ [[:lower:]]+
    exclam               ~ '!'
    delete               ~ 'delete'
    modal_strength       ~ 'modal-strength'
    polarity             ~ 'polarity'
    aspect               ~ 'aspect'
    modal_strength_value ~ 'neutral-affirmative' | 'partial-affirmative' | 'neutral-negative'
    aspect_value         ~ 'habitual'
    concept              ~ 'concept' | 'thing' | 'person'
    attr                 ~ 'functor' | 't_lemma'
    tlemma               ~ 't_lemma'
    root                 ~ 'root'
    add                  ~ 'add'
    error                ~ 'error'
    ok                   ~ 'ok'
    else                 ~ 'else'
    relation             ~ 'functor'
    colon                ~ ':'
    if                   ~ 'if'
    dash                 ~ '-'
    comma                ~ ','
    functor              ~ 'ACT' | 'PAT' | 'CPHR' | 'MANN' | 'BEN' | 'RSTR'
    new                  ~ 'NEW'
    node                 ~ 'echild' | 'no-echild' | 'esibling'
    dot                  ~ '.'

__DSL__
}

sub parse($self, $input) {
    return ${ $self->grammar->parse(\$input, __PACKAGE__) } unless $self->debug;

    warn "<<<$input>>>";
    my $recce = 'Marpa::R2::Scanless::R'->new({
        grammar            => $self->grammar,
        semantics_package  => __PACKAGE__,
        (trace_terminals   => 1,
         trace_values      => 1) x $self->debug});

    my $value;
    if (eval { $recce->read(\$input); $value = $recce->value }) {
        use Data::Dumper; warn Dumper $value;
        return $$value

    } else {
        my $eval_error = $@;
        my ($from, $length) = $recce->last_completed('Value');
        my $last;
        $last = $recce->substring($from, $length) if defined $from;
        use Data::Dumper; 
        die "Expected: @{ $recce->terminals_expected }\n$from:$last\n", $eval_error, Dumper $recce->value;
    }
}


sub _build_grammar($self) {
    my $dsl = $self->dsl;
    'Marpa::R2::Scanless::G'->new({source => $dsl})
}

=head1 NAME

Treex::Tool::UMR::PDTV2PB::Parser

=cut

__PACKAGE__
