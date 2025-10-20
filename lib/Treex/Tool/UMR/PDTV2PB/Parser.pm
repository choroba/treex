package Treex::Tool::UMR::PDTV2PB::Parser;
use utf8;
use Moose;
use experimental qw( signatures );

use Treex::Tool::UMR::PDTV2PB::Transformation;

use Marpa::R2;
use namespace::clean;

has dsl     => (is => 'ro', lazy => 1, builder => '_build_dsl');
has grammar => (is => 'ro', lazy => 1, builder => '_build_grammar');
has errors  => (is => 'ro', default => sub { [] });
has debug   => (is => 'ro', default => 0);


sub _build_dsl($) {
    return \<< '__DSL__'

    lexeme default = latm => 1

    :default           ::= action => [name,values]
    Rule               ::= Commands  action => ::first
    Commands           ::= Value                          action => ::first
                         | Value (MaybeComma) Commands    action => list
                         | Command                        action => ::first
                         | Command (MaybeComma) Commands  action => list
    MaybeComma         ::= comma
    MaybeComma         ::= 
    Value              ::= Relation                        action => ::first
                         | functor                         action => ::first
                         | Concept                         action => ::first
    Command            ::= (exclam) No_args                action => ::first
                         | (exclam) Args                   action => ::first
                         | If                              action => ::first
                         | DeleteRoot
    DeleteRoot         ::= (lpar) (exclam) delete (comma) functor (rpar)
    If                 ::= if (lpar) Conditions (rpar) (lpar) Commands (rpar) (else) Else  action => If
    Else               ::= (lpar) Commands (rpar)          action => ::first
                         | If
                         | (exclam) No_args
    Conditions         ::= NodelessConditions Conditions action => [values]
                         | Condition                     action => [values]
                         | Condition (comma) Conditions  action => append
    NodelessConditions ::= NodelessCondition             action => [values]
                         | NodelessCondition (comma) NodelessConditions action => append
    NodelessCondition  ::= tlemma (colon) Lemmas   action => nodeless_condition
                         | fattr (colon) Functors  action => nodeless_condition
    Condition          ::= Maybe_node  NodelessCondition action => condition
                         | Macro
    Macro              ::= dollar macro
    Maybe_node         ::= node (dot)  action => ::first
    Maybe_node         ::=             action => empty
    Lemmas             ::= Lemma                 action => [values]
                         | Lemma (comma) Lemmas  action => append
    Lemma              ::= lemma         action => ::first
                         | upper1 lemma  action => concat
    Functors           ::= functor  action => [values],
                         | functor (comma) Functors action => append
    Relation           ::= arg arg_num  action => concat
                         | rel_val  action => ::first
    Concept            ::= Cprefixes Csuffix action => concept_template
                         | concept           action => concat
    Csuffix            ::= csuffix           action => concat
                         | new dash csuffix  action => concat
    Cprefixes          ::= cprefix dash Cprefixes     action => concat
                         | cprefix dash functor       action => concat
                         | cprefix dash functor dash  action => concat
                         | cprefix dash               action => concat
    No_args            ::= delete  action => Delete
                         | root    action => ::first
                         | error   action => error
                         | ok      action => ok
    Args               ::= Set_modal_strength  action => ::first
                         | Set_aspect          action => ::first
                         | Set_polarity        action => ::first
                         | Set_tlemma          action => ::first
                         | Set_relation        action => ::first
                         | Add                 action => ::first
                         | Move                action => ::first
    Set_modal_strength ::= (modal_strength lpar node dot fattr colon) functor (comma) modal_strength_value (rpar)  action => node_modal_strength
                         | (modal_strength lpar) modal_strength_value (rpar)  action => modal_strength
    Set_aspect         ::= (aspect lpar) aspect_value (rpar) action => aspect
    Set_polarity       ::= (polarity lpar) dash (rpar)       action => polarity
    Set_tlemma         ::= (tlemma lpar) Concept (rpar)      action => tlemma
    Set_relation       ::= (relation lpar) Relation (rpar)   action => relation
    Add                ::= (add lpar) node_target (dot) Set_tlemma (comma) Set_relation (rpar)
    Move               ::= move (lpar) node_target (colon) functor (comma) Relation (rpar) action => [values]

    :discard             ~ whitespace
    whitespace           ~ [\s]+
    lpar                 ~ '('
    rpar                 ~ ')'
    arg                  ~ 'ARG'
    arg_num              ~ [0-9M]
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
    concept              ~ 'concept' | 'thing' | 'person' | 'relative-position' | 'umr-unknown'
    fattr                ~ 'functor'
    tlemma               ~ 't_lemma'
    root                 ~ 'root'
    add                  ~ 'add'
    move                 ~ 'move'
    error                ~ 'error'
    ok                   ~ 'ok'
    else                 ~ 'else'
    relation             ~ 'functor'
    macro                ~ 'n.denot-v' | 'n.denot' | 'noun,verb' | 'n.pron.indef' | 'lemma-not-všechen' | 'n-not-adj' | 'noun' | 'not-adj' | 'verb' | 'form:s+7' | 'form:od+2' | 'form:o+6'
    dollar               ~ '$'
    colon                ~ ':'
    if                   ~ 'if'
    dash                 ~ '-'
    comma                ~ ','
    functor              ~ 'ACT' | 'PAT' | 'EFF' | 'ADDR' | 'ORIG' | 'CPHR' | 'DPHR' | 'MANN' | 'BEN' | 'RSTR' | 'LOC' | 'DIR1' | 'REG' | 'AIM' | 'ACMP' | 'CAUS' | 'EXT'
    rel_val              ~ 'manner' | 'possessor' | 'op1' | 'quant' | 'source'
    new                  ~ 'NEW'
    node                 ~ 'echild' | 'no-echild' | 'esibling'
    node_target          ~ 'echild' | 'esibling'
    dot                  ~ '.'

__DSL__
}

sub append($, $v, $l) { [@$l, $v] }
sub empty($) { }
sub list_def($, @l) { [grep defined, @l] }

sub list($, @l) {
    'Treex::Tool::UMR::PDTV2PB::Transformation::List'->new({list => \@l})
}

sub concept_template($obj, @values) {
    'Treex::Tool::UMR::PDTV2PB::Transformation::Concept::Template'->new(
        {template => concat($obj, map ref {} eq ref ? $_->{value} : $_, @values)})
}

sub Delete($obj, $) {
    'Treex::Tool::UMR::PDTV2PB::Transformation::Delete'->new
}

sub error($obj, $) {
    'Treex::Tool::UMR::PDTV2PB::Transformation::Error'->new
}

sub ok($, $) {
    'Treex::Tool::UMR::PDTV2PB::Transformation::OK'->new
}

sub aspect($, $value) {
    'Treex::Tool::UMR::PDTV2PB::Transformation::SetAttr'->new(
        {attr  => 'aspect',
         value => $value})
}

sub polarity($, $value) {
    'Treex::Tool::UMR::PDTV2PB::Transformation::SetAttr'->new(
        {attr  => 'polarity',
         value => $value})
}

sub tlemma($, $value) {
    'Treex::Tool::UMR::PDTV2PB::Transformation::SetAttr'->new(
        {attr  => 'concept',
         value => $value})
}

sub relation($, $value) {
    'Treex::Tool::UMR::PDTV2PB::Transformation::SetAttr'->new(
        {attr  => 'functor',
         value => $value})
}

sub modal_strength($, $value) {
    'Treex::Tool::UMR::PDTV2PB::Transformation::SetAttr'->new(
        {attr  => 'modal_strength',
         value => $value})
}

sub node_modal_strength($, $functor, $value) {
    'Treex::Tool::UMR::PDTV2PB::Transformation::SetAttr'->new(
        {attr  => 'modal_strength',
         node  => $functor,
         value => $value})
}

sub If($, $if, $cond, $cmd, $else) {
    'Treex::Tool::UMR::PDTV2PB::Transformation::If'->new({cond => $cond,
                                                          then => $cmd,
                                                          else => $else})
}

sub nodeless_condition($, $attr, $values) {
    'Treex::Tool::UMR::PDTV2PB::Transformation::Condition'->new(
        {attr => $attr,
         values => $values})
}

sub condition($, $node, $condition) {
    'Treex::Tool::UMR::PDTV2PB::Transformation::Condition'->new(
        {%$condition, node => $node})
}

sub concat($, @values) {
    'Treex::Tool::UMR::PDTV2PB::Transformation::String'->new({
        value => [map ref ? @{ $_->{value} } : $_, @values]})
}

use Data::Dumper;

sub parse($self, $input) {
    return ${ $self->grammar->parse(\$input, __PACKAGE__) } unless $self->debug;

    warn "<<<$input>>>" if $self->debug;
    my $recce = 'Marpa::R2::Scanless::R'->new({
        grammar            => $self->grammar,
        semantics_package  => __PACKAGE__,
        (trace_terminals   => 1,
         trace_values      => 1) x $self->debug});

    my $value;
    if (eval { $recce->read(\$input); $value = $recce->value }) {
        warn Dumper PARSED => $value if $self->debug;
        return $$value

    } else {
        my $eval_error = $@;
        my ($from, $length) = $recce->last_completed('Value');
        my $last;
        $last = $recce->substring($from, $length) if defined $from;
        push @{ $self->errors }, "<<$input>>\nExpected: @{ $recce->terminals_expected }\n$from:$last\n" . $eval_error . Dumper $recce->value;
        return \ []
    }
}

sub die_if_errors($self) {
    die @{ $self->errors } if @{ $self->errors };
}

sub _build_grammar($self) {
    my $dsl = $self->dsl;
    'Marpa::R2::Scanless::G'->new({source => $dsl})
}

=head1 NAME

Treex::Tool::UMR::PDTV2PB::Parser

=cut

__PACKAGE__
