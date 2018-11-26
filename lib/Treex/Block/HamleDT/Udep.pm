package Treex::Block::HamleDT::Udep;
use utf8;
use open ':utf8';
use Moose;
use Treex::Core::Common;
use Treex::Tool::PhraseBuilder::PragueToUD;
extends 'Treex::Core::Block';

has store_orig_filename => (is=>'ro', isa=>'Bool', default=>1);

has 'last_loaded_from' => ( is => 'rw', isa => 'Str', default => '' );
has 'sent_in_file'     => ( is => 'rw', isa => 'Int', default => 0 );

#------------------------------------------------------------------------------
# Reads a Prague-style tree and transforms it to Universal Dependencies.
#------------------------------------------------------------------------------
sub process_atree {
    my ($self, $root) = @_;

    # Add the name of the input file and the number of the sentence inside
    # the file as a comment that will be written in the CoNLL-U format.
    # (In any case, Write::CoNLLU will print the sentence id. But this additional
    # information is also very useful for debugging, as it ensures a user can find the sentence in Tred.)
    if ($self->store_orig_filename){
        my $bundle = $root->get_bundle();
        my $loaded_from = $bundle->get_document()->loaded_from(); # the full path to the input file
        my $file_stem = $bundle->get_document()->file_stem(); # this will be used in the comment
        if($loaded_from eq $self->last_loaded_from()) {
            $self->set_sent_in_file($self->sent_in_file() + 1);
        } else {
            $self->set_last_loaded_from($loaded_from);
            $self->set_sent_in_file(1);
        }
        my $sent_in_file = $self->sent_in_file();
        my $comment = "orig_file_sentence $file_stem\#$sent_in_file";
        my @comments;
        if(defined($bundle->wild()->{comment})) {
            @comments = split(/\n/, $bundle->wild()->{comment});
        }
        if (! any {$_ eq $comment} (@comments)) {
            push(@comments, $comment);
            $bundle->wild()->{comment} = join("\n", @comments);
        }
    }

    # Now the harmonization proper.
    $self->exchange_tags($root);
    $self->fix_symbols($root);
    $self->fix_annotation_errors($root);
    $self->convert_deprels($root);
    $self->remove_null_pronouns($root);
    $self->relabel_appos_name($root);
    # The most difficult part is detection of coordination, prepositional and
    # similar phrases and their interaction. It will be done bottom-up using
    # a tree of phrases that will be then projected back to dependencies, in
    # accord with the desired annotation style. See Phrase::Builder for more
    # details on how the source tree is decomposed. The construction parameters
    # below say how should the resulting dependency tree look like. The code
    # of the builder knows how the INPUT tree looks like (including the deprels
    # already converted from Prague to the UD set).
    my $builder = Treex::Tool::PhraseBuilder::PragueToUD->new(
        'prep_is_head'           => 0,
        'cop_is_head'            => 0,
        'coordination_head_rule' => 'first_conjunct',
        'counted_genitives'      => $root->language ne 'la'
    );
    my $phrase = $builder->build($root);
    $phrase->project_dependencies();
    # The 'cop' relation can be recognized only after transformations.
    $self->tag_copulas_aux($root);
    # Look for prepositional objects (must be done after transformations).
    $self->relabel_prepositional_objects($root);
    $self->change_case_to_mark_under_verb($root);
    $self->dissolve_chains_of_auxiliaries($root);
    $self->fix_jak_znamo($root);
    $self->classify_numerals($root);
    $self->relabel_subordinate_clauses($root);
    $self->check_ncsubjpass_when_auxpass($root);
    $self->raise_punctuation_from_coordinating_conjunction($root);
    ###!!! The EasyTreex extension of Tred currently does not display values of the deprel attribute.
    ###!!! Copy them to conll/deprel (which is displayed) until we make Tred know deprel.
    my @nodes = $root->get_descendants({'ordered' => 1});
    if(1)
    {
        foreach my $node (@nodes)
        {
            my $upos = $node->iset()->upos();
            my $ufeat = join('|', $node->iset()->get_ufeatures());
            $node->set_tag($upos);
            $node->set_conll_cpos($upos);
            $node->set_conll_feat($ufeat);
            $node->set_conll_deprel($node->deprel());
            $node->set_afun(undef); # just in case... (should be done already)
        }
    }
    # Some of the above transformations may have split or removed nodes.
    # Make sure that the full sentence text corresponds to the nodes again.
    ###!!! Note that for the Prague treebanks this may introduce unexpected differences.
    ###!!! If there were typos in the underlying text or if numbers were normalized from "1,6" to "1.6",
    ###!!! the sentence attribute contains the real input text, but it will be replaced by the normalized word forms now.
    $root->get_zone()->set_sentence($root->collect_sentence_text());
}



#------------------------------------------------------------------------------
# Replaces the tag from the original corpus by the corresponding Universal POS
# tag; saves the original tag in conll/pos instead. This would be done also in
# Write::CoNLLU. But even if we write Treex and view it in Tred, we want the UD
# tree to display the UPOS tags.
#------------------------------------------------------------------------------
sub exchange_tags
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants();
    foreach my $node (@nodes)
    {
        my $original_tag = $node->tag();
        $node->set_tag($node->iset()->get_upos());
        ###!!! Do not do this now! If we were converting via Prague, the $original_tag now contains a PDT-style tag.
        ###!!! On the other hand, already the Prague harmonization stored the really original tag in conll/pos.
        #$node->set_conll_pos($original_tag);
    }
}



#------------------------------------------------------------------------------
# Some treebanks do not distinguish symbols from punctuation. This method fixes
# this for a few listed symbols. Some other treebanks tag symbols as the words
# they substitute for (e.g. '%' is NOUN but it should be SYM).
#------------------------------------------------------------------------------
sub fix_symbols
{
    my $self  = shift;
    my $root  = shift;
    my @nodes = $root->get_descendants();
    foreach my $node (@nodes)
    {
        # '%' (percent) and '$' (dollar) will be tagged SYM regardless their
        # original part of speech (probably PUNCT or NOUN). Note that we do not
        # require that the token consists solely of the symbol character.
        # Especially with '$' there are tokens like 'US$', 'CR$' etc. that
        # should be included.
        if($node->form() =~ m/[\$%]$/)
        {
            $node->iset()->set('pos', 'sym');
            # If the original dependency relation was AuxG, it should be changed but there is no way of knowing the correct relation.
            # The underlying words are nouns, hence they could be Sb, Obj, Adv, Atr, Apposition or even Pnom.
        }
        elsif($node->is_punctuation())
        {
            # Note that some characters cannot be decided in this simple way.
            # For example, '-' is either punctuation (hyphen) or symbol (minus)
            # but we cannot tell them apart automatically if we do not understand the sentence.
            if($node->form() =~ m/^[\+=]$/)
            {
                $node->iset()->set('pos', 'sym');
                if($node->deprel() eq 'AuxG')
                {
                    $node->set_deprel('AuxY');
                }
            }
            # Slash '/' can be punctuation or mathematical symbol.
            # It is difficult to tell automatically but we will make it a symbol if it is not leaf (and does not head coordination).
            elsif($node->form() eq '/' && !$node->is_leaf() && $node->deprel() !~ m/^(Coord|Apos)$/)
            {
                $node->iset()->set('pos', 'sym');
                if($node->deprel() eq 'AuxG')
                {
                    $node->set_deprel('AuxY');
                }
                my $parent = $node->parent();
                my @children = $node->children();
                foreach my $child (@children)
                {
                    $child->set_parent($parent);
                }
            }
        }
        # The letter 'x' sometimes substitutes the multiplication symbol '×'.
        elsif($node->form() eq 'x' && $node->is_conjunction())
        {
            $node->iset()->set('pos', 'sym');
            if($node->deprel() eq 'AuxG')
            {
                $node->set_deprel('AuxY');
            }
        }
    }
}



#------------------------------------------------------------------------------
# Convert analytical functions to universal dependency relations.
# This new version (2015-03-25) is meant to act before any structural changes,
# even before coordination gets reshaped.
#------------------------------------------------------------------------------
sub convert_deprels
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants();
    # We will need to query the original Prague deprel (afun) of parent nodes in certain situations.
    # It will not be guaranteed that the parent deprel has not been converted by then. Therefore we will make a copy now.
    # Make sure that the copy is defined even if the parent is root.
    $root->wild()->{prague_deprel} = 'AuxS';
    foreach my $node (@nodes)
    {
        my $deprel = $node->deprel() // '';
        $node->wild()->{prague_deprel} = $deprel;
    }
    foreach my $node (@nodes)
    {
        my $deprel = $node->deprel();
        $deprel = '' if(!defined($deprel));
        my $parent = $node->parent();
        # The top nodes (children of the root) must be labeled 'root'.
        # However, this will be solved elsewhere (and tree transformations may
        # result in a different node being attached to the root), so we will
        # now treat the labels as if nothing were attached to the root.
        # Punctuation is always 'punct' unless it depends directly on the root (which should happen only if there is just one node and the root).
        # We will temporarily extend the label if it heads coordination so that the coordination can later be reshaped properly.
        if($node->is_punctuation())
        {
            if($deprel eq 'Coord')
            {
                $deprel = 'coord';
            }
            else
            {
                $deprel = 'punct';
            }
        }
        # Coord marks the conjunction that heads a coordination.
        # (Punctuation heading coordination has been processed earlier.)
        # Coordinations will be later restructured and the conjunction will be attached as 'cc'.
        elsif($deprel eq 'Coord')
        {
            $deprel = 'coord';
        }
        # AuxP marks a preposition. There are two possibilities:
        # 1. It heads a prepositional phrase. The relation of the phrase to its parent is marked at the argument of the preposition.
        # 2. It is a leaf, attached to another preposition, forming a multi-word preposition. (In this case the word can be even a noun.)
        # Prepositional phrases will be later restructured. In the situation 1, the preposition will be attached to its argument as 'case'.
        # In the situation 2, the first word in the multi-word prepositon will become the head and all other parts will be attached to it as 'fixed'.
        elsif($deprel eq 'AuxP')
        {
            $deprel = 'case';
        }
        # AuxC marks a subordinating conjunction that heads a subordinate clause.
        # It will be later restructured and the conjunction will be attached to the subordinate predicate as 'mark'.
        elsif($deprel eq 'AuxC')
        {
            $deprel = 'mark';
        }
        # Predicate: If the node is not the main predicate of the sentence and it has the Pred deprel,
        # then it is probably the main predicate of a parenthetical expression.
        # Exception: predicates of coordinate main clauses. This must be solved after coordinations have been reshaped. ###!!! TODO
        elsif($deprel eq 'Pred')
        {
            $deprel = 'parataxis';
        }
        # Subject: nsubj, nsubj:pass, csubj, csubj:pass
        elsif($deprel eq 'Sb')
        {
            # Is the parent a passive verb?
            # Note that this will not catch all passives (e.g. reflexive passives).
            # Thus we will later check whether there is an aux:pass sibling.
            if($parent->iset()->is_passive())
            {
                # If this is a verb (including infinitive) then it is a clausal subject.
                $deprel = $node->is_verb() ? 'csubj:pass' : 'nsubj:pass';
            }
            else # Parent is not passive.
            {
                # If this is a verb (including infinitive) then it is a clausal subject.
                $deprel = $node->is_verb() ? 'csubj' : 'nsubj';
            }
        }
        # Object: obj, iobj, ccomp, xcomp
        elsif($deprel eq 'Obj')
        {
            ###!!! If a verb has two or more objects, we should select one direct object and the others will be indirect.
            ###!!! We would probably have to consider all valency frames to do that properly.
            ###!!! TODO: An approximation that we probably could do in the meantime is that
            ###!!! if there is one accusative and one or more non-accusatives, then the accusative is the direct object.
            if($node->is_verb())
            {
                # If this is an infinitive then it is an xcomp (controlled clausal complement).
                # If this is a verb form other than infinitive then it is a ccomp.
                ###!!! TODO: But if the infinitive is part of periphrastic future, then it is ccomp, not xcomp!
                $deprel = $node->is_infinitive() ? 'xcomp' : 'ccomp';
            }
            else # nominal object
            {
                # New in UD 2.1 for case-marking Indo-European languages:
                # Prepositional objects are no longer "obj" but they are also not plain "obl".
                # Instead, they get a special subtype, "obl:arg".
                # We convert deprels before the structure is changed, so we can
                # ask whether the direct parent node is a preposition.
                ###!!! This will not work properly if there is coordination!
                ###!!! We should recheck the structure when it has been transformed
                ###!!! to UD, and see whether there are any "case" dependents.
                $deprel = $parent->is_adposition() ? 'obl:arg' : 'obj';
            }
        }
        # Nominal predicate attached to a copula verb.
        elsif($deprel eq 'Pnom')
        {
            # We will later transform the structure so that copula depends on the nominal predicate.
            # The 'pnom' label will disappear and the inverted relation will be labeled 'cop'.
            # We cannot do this if the predicate is a subordinate clause ("my opinion is that we should not go there"). Then a verb would have two subjects.
            if($node->is_verb() && !$node->is_participle())
            {
                $deprel = 'ccomp';
            }
            # The symbol "=" is tagged SYM and substitutes a verb ("equals to"). This verb is not considered copula (only "to be" is copula).
            # Hence we will re-classify the relation as object.
            elsif(!$parent->is_root() && $parent->form() eq '=')
            {
                $deprel = 'obj';
            }
            else
            {
                $deprel = 'pnom';
            }
        }
        # Adverbial modifier: advmod, obl, advcl
        elsif($deprel eq 'Adv')
        {
            ###!!! Manual disambiguation is needed here. For example, in Czech:
            ###!!! Úroda byla v tomto roce o mnoho lepší než loni.
            ###!!! There should be obl(lepší, roce) but nmod(lepší, mnoho).
            $deprel = $node->is_verb() ? 'advcl' : ($node->is_noun() || $node->is_adjective() || $node->is_numeral()) ? 'obl' : 'advmod';
        }
        # Attribute of a noun: amod, nummod, nmod, acl
        elsif($deprel eq 'Atr')
        {
            # Cardinal number is nummod, ordinal number is amod. It should not be a problem because Interset should categorize ordinals as special types of adjectives.
            # But we cannot use the is_numeral() method because it returns true if pos=num or if numtype is not empty.
            # We also want to exclude pronominal numerals (kolik, tolik, mnoho, málo). These should be det.
            if($node->iset()->pos() eq 'num')
            {
                if($node->iset()->prontype() eq '')
                {
                    # If we later push the numeral down, we will label it nummod:gov.
                    $deprel = 'nummod';
                }
                else
                {
                    # If we later push the quantifier down, we will label it det:numgov.
                    $deprel = 'det:nummod';
                }
            }
            # Names and surnames should be connected using flat or flat:name, the first node is the head.
            # The flat structure extends to titles and occupations such as "Mr.", "professor", "president",
            # provided that they agree with the name in gender, number and case, and they precede the name (at least in Czech).
            elsif($parent->iset()->nametype() =~ m/(giv|sur|prs)/ &&
                  ($node->iset()->nametype() =~ m/(giv|sur|prs)/ ||
                   $node->ord() < $parent->ord() &&
                   $node->is_noun() && !$node->is_pronominal() &&
                   $node->iset()->gender() eq $parent->iset()->gender() &&
                   $node->iset()->animacy() eq $parent->iset()->animacy() &&
                   $node->iset()->number() eq $parent->iset()->number() &&
                   $node->iset()->case() eq $parent->iset()->case()))
            {
                $deprel = 'flat';
            }
            elsif($node->is_foreign() && $parent->is_foreign() ||
                  $node->is_foreign() && $node->is_adposition() && $parent->is_proper_noun())
                  ###!!! van Gogh, de Gaulle in Czech text; but it means we will have to reverse the relation left-to-right!
                  ###!!! Another solution would be to label the relation "case". But foreign prepositions do not have this function in Czech.
            {
                $deprel = 'flat:foreign';
            }
            elsif($node->is_determiner() && $self->agree($node, $parent, 'case'))
            {
                $deprel = 'det';
            }
            elsif($node->is_adjective())
            {
                $deprel = 'amod';
            }
            elsif($node->is_adverb())
            {
                $deprel = 'advmod';
            }
            elsif($node->is_verb())
            {
                $deprel = 'acl';
            }
            else
            {
                $deprel = 'nmod';
            }
        }
        # AuxA is not an official deprel used in HamleDT 2.0. Nevertheless it has been introduced in some (not all)
        # languages by people who want to use the resulting data in TectoMT. It marks articles attached to nouns.
        elsif($deprel eq 'AuxA')
        {
            $deprel = 'det';
        }
        # Verbal attribute is analyzed as secondary predication.
        ###!!! TODO: distinguish core arguments (xcomp) from non-core arguments and adjuncts (acl/advcl).
        elsif($deprel =~ m/^AtvV?$/)
        {
            $deprel = 'xcomp';
        }
        # Auxiliary verb "být" ("to be"): aux, aux:pass
        elsif($deprel eq 'AuxV')
        {
            # The Czech conditional auxiliary "by" is not aux:pass even if attached to a passive verb.
            $deprel = $parent->iset()->is_passive() && !$node->is_conditional() ? 'aux:pass' : 'aux';
            # Side effect: We also want to modify Interset. The PDT tagset does not distinguish auxiliary verbs but UPOS does.
            $node->iset()->set('verbtype', 'aux');
        }
        # Reflexive pronoun "se", "si" with inherently reflexive verbs.
        # Unfortunately, previous harmonization to the Prague style abused the AuxT label to also cover Germanic verbal particles and other compound-like stuff with verbs.
        # We have to test for reflexivity if we want to output expl:pv!
        elsif($deprel eq 'AuxT')
        {
            # This appears in Slavic languages, although in theory it could be used in some Romance and Germanic languages as well.
            # It actually also appears in Dutch (but we mixed it with verbal particles there).
            # Most Dutch pronouns used with this label are tagged as reflexive but a few are not.
            if($node->is_reflexive() || $node->is_pronoun())
            {
                $deprel = 'expl:pv';
            }
            # The Tamil deprel CC (compound) has also been converted to AuxT. 11 out of 12 occurrences are tagged as verbs.
            elsif($node->is_verb())
            {
                $deprel = 'compound';
            }
            # Germanic verbal particles can be tagged as various parts of speech, including adpositions. Hence we cannot distinguish them from
            # preposition between finite verb and infinitive, which appears in Portuguese. Examples: continua a manter; deixa de ser
            # en: 1181 PART, 28 ADP, 28 ADV, 3 ADJ; 27 different lemmas: 418 up, 261 out, 141 off...
            # de: 4002 PART; 138 different lemmas: 528 an, 423 aus, 350 ab...
            # nl: 1097 ADV, 460 PRON, 397 X, 176 ADJ, 157 NOUN, 99 ADP, 42 VERB, 9 SCONJ; 368 different lemmas: 402 zich, 178 uit, 167 op, 112 aan...
            # pt: 587 ADP, 53 SCONJ, 1 ADV; 5 different lemmas: 432 a, 114 de, 56 que, 38 por, 1 para
            else
            {
                $deprel = 'compound:prt';
            }
        }
        # Reflexive pronoun "se", "si" used for reflexive passive.
        elsif($deprel eq 'AuxR')
        {
            $deprel = 'expl:pass';
        }
        # AuxZ: intensifier or negation
        elsif($deprel eq 'AuxZ')
        {
            my $lemma = $node->lemma();
            # AuxZ is an emphasizing word (“especially on Monday”).
            # It also occurs with numbers (“jen čtyři firmy”, “jen několik procent”).
            # The word "jen" ("only") is not necessarily a restriction. It rather emphasizes that the number is a restriction.
            # On the tectogrammatical layer these words often get the functor RHEM (rhematizer / rematizátor = něco, co vytváří réma, fokus).
            # But this is not a 1-1 mapping.
            # https://ufal.mff.cuni.cz/pdt2.0/doc/manuals/en/t-layer/html/ch10s06.html
            # https://ufal.mff.cuni.cz/pdt2.0/doc/manuals/en/t-layer/html/ch07s07s05.html
            # Most frequent lemmas with AuxZ: i (4775 výskytů), jen, až, pouze, ani, už, již, ještě, také, především (689 výskytů)
            # Most frequent t-lemmas with RHEM: #Neg (7589 výskytů), i, jen, také, už, již, ani, až, pouze, například (500 výskytů)
            $deprel = 'advmod:emph';
        }
        # Neg: used in Prague-style harmonization of some treebanks (e.g. Romanian) for negation (elsewhere it may be AuxZ or Adv).
        elsif($deprel eq 'Neg')
        {
            # There was a separate 'neg' relation in UD v1 but it was removed in UD v2.
            $deprel = 'advmod';
        }
        # The AuxY deprel is used in various situations, see below.
        elsif($deprel eq 'AuxY')
        {
            # When it is attached to a subordinating conjunction (AuxC), the two form a multi-word subordinator.
            # Index Thomisticus examples: ita quod (so that), etiam si (even if), quod quod (what is that), ac si (as if), et si (although)
            if($parent->wild()->{prague_deprel} eq 'AuxC')
            {
                # The phrase builder will later transform it to MWE.
                $deprel = 'mark';
            }
            # When it is attached to a complement (Atv, AtvV), it is usually an equivalent of the subordinating conjunction "as" and it should be 'mark'.
            # Czech: "jako" ("as"); sometimes it is attached even to Obj (of verbal adjectives). It should never get the 'cc' deprel, so we will mention it explicitly.
            # Index Thomisticus examples: ut (as), sicut (as), quasi (as), tanquam (like), utpote (as) etc.
            elsif($parent->wild()->{prague_deprel} =~ m/^AtvV?$/ ||
                  lc($node->form()) =~ m/^(jako|ut|sicut|quasi|tanquam|utpote)$/)
            {
                $deprel = 'mark';
            }
            # AuxY may be a preposition attached to an adverb; unlike normal AuxP prepositions, this one is not the head.
            # Index Thomisticus: ad invicem (each other); "invicem" is adverb that could be roughly translated as "mutually".
            elsif($node->is_adposition())
            {
                $deprel = 'case';
            }
            # When it is attached to a verb, it is a sentence adverbial, disjunct or connector.
            # Index Thomisticus examples: igitur (therefore), enim (indeed), unde (whence), sic (so, thus), ergo (therefore).
            elsif($parent->is_verb() && !$node->is_coordinator())
            {
                $deprel = 'advmod';
            }
            # Non-head conjunction in coordination is probably the most common usage.
            # Index Thomisticus examples: et (and), enim (indeed), vel (or), igitur (therefore), neque (neither).
            else
            {
                $deprel = 'cc';
            }
        }
        # AuxO: redundant "to" or "si" ("co to znamená pátý postulát dokázat").
        elsif($deprel eq 'AuxO')
        {
            $deprel = 'discourse';
        }
        # Apposition
        elsif($deprel eq 'Apposition')
        {
            $deprel = 'appos';
        }
        # Punctuation
        ###!!! Since we now label all punctuation (decided by Interset) as punct,
        ###!!! here we only get non-punctuation labeled (by mistake?) AuxG, AuxX or AuxK. What to do with this???
        elsif($deprel eq 'AuxG')
        {
            # AuxG is intended for graphical symbols other than comma and the sentence-terminating punctuation.
            # It is mostly assigned to punctuation but sometimes to symbols (% $ + x) or even alphanumeric tokens (1 2 3).
            # The 'punct' deprel should be used only for punctuation.
            # We do not really know what the label should be in this case.
            # For mathematical operators (+ - x /) it should be probably 'cc'.
            # (But we cannot distinguish minus from hyphen, so with '-' we will not get here. Same for '/'.)
            # For % and $ it could be any label used with noun phrases.
            if($node->form() =~ m/^[+x]$/)
            {
                $deprel = 'cc';
            }
            else
            {
                $deprel = 'nmod'; ###!!! or nsubj or obj or whatever
            }
        }
        elsif($deprel =~ m/^Aux[XK]$/)
        {
            # AuxX is reserved for commas.
            # AuxK is used for sentence-terminating punctuation, usually a period, an exclamation mark or a question mark.
            log_warn("Node '".$node->form()."' has deprel '$deprel' but it is not punctuation.");
            $deprel = 'punct';
        }
        ###!!! TODO: ExD with chains of orphans should be stanfordized!
        elsif($deprel eq 'ExD')
        {
            # Some ExD are vocatives.
            if($node->iset()->case() eq 'voc')
            {
                $deprel = 'vocative';
            }
            # Some ExD are properties or quantities compared to.
            ###!!! This is specific to Czech!
            elsif(defined($parent->lemma()) && $parent->lemma() =~ m/^(jako|než)$/)
            {
                $deprel = 'advcl';
            }
            else
            {
                $deprel = 'dep';
            }
        }
        # Set up a fallback so that $deprel is always defined.
        else
        {
            $deprel = 'dep:'.lc($deprel);
        }
        # Save the universal dependency relation label with the node.
        $node->set_deprel($deprel);
    }
    # Now that all deprels have been converted we do not need the copies of the original deprels any more. Delete them.
    delete($root->wild()->{prague_deprel});
    foreach my $node (@nodes)
    {
        delete($node->wild()->{prague_deprel});
    }
}



#------------------------------------------------------------------------------
# Prepositional objects are considered oblique in many languages, although this
# is not a universal rule. They should be labeled "obl:arg" instead of "obj".
# We have tried to identify them during deprel conversion but some may have
# slipped through because of interaction with coordination or apposition.
#------------------------------------------------------------------------------
sub relabel_prepositional_objects
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants();
    foreach my $node (@nodes)
    {
        if($node->deprel() =~ m/^i?obj(:|$)/)
        {
            ###!!! In Slavic languages, this condition does not work well with
            ###!!! some quantified noun phrases, e.g. in Czech:
            ###!!! Výbuch zranil kolem padesáti lidí.
            ###!!! ("Kolem padesáti lidí" = "around fifty people" acts externally
            ###!!! as neuter singular accusative, but internally its head "lidí"
            ###!!! is masculine plural genitive and has a prepositional child.)
            if(any {$_->deprel() =~ m/^case(:|$)/} ($node->children()))
            {
                $node->set_deprel('obl:arg');
            }
        }
    }
}



#------------------------------------------------------------------------------
# Since UD v2, verbal copulas must be tagged AUX and not VERB. We cannot check
# this during the deprel conversion because we do not always see the real
# copula as the parent of the Pnom node (hint: coordination).
#------------------------------------------------------------------------------
sub tag_copulas_aux
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants();
    foreach my $node (@nodes)
    {
        if($node->deprel() eq 'cop' && $node->is_verb())
        {
            $node->iset()->set('verbtype', 'aux');
            $node->set_tag('AUX');
        }
    }
}



#------------------------------------------------------------------------------
# The AnCora treebanks of Catalan and Spanish contain empty nodes representing
# elided subjects. These nodes are typically leaves (but I don't know whether
# it is guaranteed). Remove them.
#------------------------------------------------------------------------------
sub remove_null_pronouns
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants();
    foreach my $node (@nodes)
    {
        if($node->form() eq '_' && $node->is_pronoun())
        {
            if($node->is_leaf())
            {
                $node->remove();
            }
            else
            {
                log_warn('Cannot remove NULL node that is not leaf.');
            }
        }
    }
}



#------------------------------------------------------------------------------
# In the Croatian SETimes corpus, given name of a person depends on the family
# name, and the relation is labeled as apposition. Change the label to 'flat'.
# This should be done before we start structural transformations.
#------------------------------------------------------------------------------
sub relabel_appos_name
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants();
    foreach my $node (@nodes)
    {
        my $deprel = $node->deprel();
        if(defined($deprel) && $deprel eq 'appos')
        {
            my $parent = $node->parent();
            next if($parent->is_root());
            if($node->is_proper_noun() && $parent->is_proper_noun() && $self->agree($node, $parent, 'case'))
            {
                $node->set_deprel('flat');
            }
        }
    }
}



#------------------------------------------------------------------------------
# Makes sure that a preposition attached to a verb is labeled 'mark' and not
# 'case'. It is difficult to enforce during restructuring of Aux[PC] phrases
# because there are things like coordinations of AuxP-AuxC chains, so it is not
# immediately apparent that the final head will be a verb.
#------------------------------------------------------------------------------
sub change_case_to_mark_under_verb
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants();
    foreach my $node (@nodes)
    {
        if($node->deprel() eq 'case' && $node->parent()->is_verb())
        {
            $node->set_deprel('mark');
        }
    }
}



#------------------------------------------------------------------------------
# If a verb has an aux:pass or expl:pass child, its subject must be also *pass.
# We try to get the subjects right already during deprel conversion, checking
# whether the parent is a passive participle. But that will not work for
# reflexive passives, where we have to wait until the reflexive pronoun has its
# deprel. Probably it will also not work if the participle does not have the
# voice feature because its function is not limited to passive (such as in
# English). This method will fix it. It should be called after the main part of
# conversion is done (otherwise coordination could obscure the passive
# auxiliary).
#------------------------------------------------------------------------------
sub check_ncsubjpass_when_auxpass
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants();
    foreach my $node (@nodes)
    {
        my @children = $node->children();
        my @auxpass = grep {$_->deprel() =~ m/^(aux|expl):pass$/} (@children);
        if(scalar(@auxpass) > 0)
        {
            foreach my $child (@children)
            {
                if($child->deprel() eq 'nsubj')
                {
                    $child->set_deprel('nsubj:pass');
                }
                elsif($child->deprel() eq 'csubj')
                {
                    $child->set_deprel('csubj:pass');
                }
                # Specific to some languages only: if the oblique agent is expressed, it is a bare instrumental noun phrase.
                # In the Prague-style annotation, it would be labeled as "obj" when we come here.
                elsif($child->deprel() eq 'obj' && $child->is_instrumental())
                {
                    $child->set_deprel('obl:agent');
                }
            }
        }
    }
}



#------------------------------------------------------------------------------
# UD guidelines disallow chains of auxiliary verbs. Regardless whether there is
# hierarchy in application of grammatical rules, all auxiliaries should be
# attached directly to the main verb (example [en] "could have been done").
#------------------------------------------------------------------------------
sub dissolve_chains_of_auxiliaries
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants();
    foreach my $node (@nodes)
    {
        # An auxiliary verb may be attached to another auxiliary verb in coordination ([cs] "byl a bude prodáván").
        # Thus we must check whether the deprel is aux (or aux:pass). We also cannot dissolve the chain if the
        # grandparent is root.
        if($node->iset()->is_auxiliary() && $node->parent()->iset()->is_auxiliary() && $node->deprel() =~ m/^aux/ && !$node->parent()->parent()->is_root())
        {
            $node->set_parent($node->parent()->parent());
        }
    }
}



#------------------------------------------------------------------------------
# Punctuation in coordination is sometimes attached to a non-head conjunction
# instead to the head (e.g. in Index Thomisticus). Now all coordinating
# conjunctions are attached to the first conjunct and so should be commas.
#------------------------------------------------------------------------------
sub raise_punctuation_from_coordinating_conjunction
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants();
    foreach my $node (@nodes)
    {
        if($node->deprel() eq 'punct')
        {
            my $parent = $node->parent();
            my $pdeprel = $parent->deprel() // '';
            if($pdeprel eq 'cc')
            {
                $node->set_parent($parent->parent());
            }
        }
    }
}



#------------------------------------------------------------------------------
# The two Czech words "jak známo" ("as known") are attached as ExD siblings in
# the Prague style because there is missing copula. However, in UD the nominal
# predicate "známo" is the head.
#------------------------------------------------------------------------------
sub fix_jak_znamo
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants({'ordered' => 1});
    for(my $i = 0; $i<$#nodes; $i++)
    {
        my $n0 = $nodes[$i];
        my $n1 = $nodes[$i+1];
        if(defined($n0->form()) && lc($n0->form()) eq 'jak' &&
           defined($n1->form()) && lc($n1->form()) eq 'známo' &&
           $n0->parent() == $n1->parent())
        {
            $n0->set_parent($n1);
            $n0->set_deprel('mark');
            $n1->set_deprel('advcl') if(!defined($n1->deprel()) || $n1->deprel() eq 'dep');
            # If the expression is delimited by commas, the commas should be attached to "známo".
            if($i>0 && $nodes[$i-1]->parent() == $n1->parent() && defined($nodes[$i-1]->form()) && $nodes[$i-1]->form() =~ m/^[-,]$/)
            {
                $nodes[$i-1]->set_parent($n1);
                $nodes[$i-1]->set_deprel('punct');
            }
            if($i+2<=$#nodes && $nodes[$i+2]->parent() == $n1->parent() && defined($nodes[$i+2]->form()) && $nodes[$i+2]->form() =~ m/^[-,]$/)
            {
                $nodes[$i+2]->set_parent($n1);
                $nodes[$i+2]->set_deprel('punct');
            }
        }
    }
}



#------------------------------------------------------------------------------
# Splits numeral types that have the same tag in the PDT tagset and the
# Interset decoder cannot distinguish them because it does not see the word
# forms.
#------------------------------------------------------------------------------
sub classify_numerals
{
    my $self  = shift;
    my $root  = shift;
    my @nodes = $root->get_descendants();
    foreach my $node (@nodes)
    {
        my $iset = $node->iset();
        # Separate multiplicative numerals (jednou, dvakrát, třikrát) and
        # adverbial ordinal numerals (poprvé, podruhé, potřetí).
        if($iset->numtype() eq 'mult')
        {
            # poprvé, podruhé, počtvrté, popáté, ..., popadesáté, posté
            # potřetí, potisící
            if($node->form() =~ m/^po.*[éí]$/i)
            {
                $iset->set('numtype', 'ord');
            }
        }
        # Separate generic numerals
        # for number of kinds (obojí, dvojí, trojí, čtverý, paterý) and
        # for number of sets (oboje, dvoje, troje, čtvery, patery).
        elsif($iset->numtype() eq 'gen')
        {
            if($iset->variant() eq '1')
            {
                $iset->set('numtype', 'sets');
            }
        }
        # Separate agreeing adjectival indefinite numeral "nejeden" (lit. "not one" = "more than one")
        # from indefinite/demonstrative adjectival ordinal numerals (několikátý, tolikátý).
        elsif($node->is_adjective() && $iset->contains('numtype', 'ord') && $node->lemma() eq 'nejeden')
        {
            $iset->add('pos' => 'num', 'numtype' => 'card', 'prontype' => 'ind');
        }
    }
}



#------------------------------------------------------------------------------
# Checks agreement between two nodes in one Interset feature. An empty value
# agrees with everything (because it can be interpreted as "any value").
#------------------------------------------------------------------------------
sub agree
{
    my $self = shift;
    my $node1 = shift;
    my $node2 = shift;
    my $feature = shift;
    my $i1 = $node1->iset();
    my $i2 = $node2->iset();
    return 1 if($i1->get($feature) eq '' || $i2->get($feature) eq '');
    return 1 if($i1->get_joined($feature) eq $i2->get_joined($feature));
    # If one or both the nodes have multiple values of the feature and their
    # intersection is not empty, take it as agreement.
    my @v1 = $i1->get_list($feature);
    foreach my $v1 (@v1)
    {
        return 1 if($i2->contains($feature, $v1));
    }
    return 0;
}



#------------------------------------------------------------------------------
# Fixes annotation errors. In the Czech PDT, abbreviations are sometimes
# confused with prepositions. For example, "s.r.o." ("společnost s ručením
# omezeným" = "Ltd.") is tokenized as "s . r . o ." and both "s" and "o" could
# also be prepositions. Sometimes it happens that morphological analysis is
# correct (abbreviated NOUN resp. ADJ) but syntactic analysis is not (the
# incoming edge is labeled AuxP).
#------------------------------------------------------------------------------
sub fix_annotation_errors
{
    my $self  = shift;
    my $root  = shift;
    my @nodes = $root->get_descendants();
    foreach my $node (@nodes)
    {
        my $form = $node->form() // '';
        my $lemma = $node->lemma() // '';
        my $pos  = $node->iset()->pos();
        my $deprel = $node->deprel();
        if($form =~ m/^[so]$/i && !$node->is_adposition() && $deprel eq 'AuxP')
        {
            # We do not know what the correct deprel would be. There is a chance it would be Apposition or Atr but it is not guaranteed.
            # On the other hand, any of the two, even if incorrect, is much better than AuxP, which would trigger various transformations,
            # inappropriate in this context.
            $node->set_deprel('Atr');
        }
        # Fix unknown tags of punctuation. If the part of speech is unknown and the form consists only of punctuation characters,
        # set the part of speech to PUNCT. This occurs in the Ancient Greek Dependency Treebank.
        elsif($pos eq '' && $form =~ m/^\pP+$/)
        {
            $node->iset()->set_pos('punc');
        }
        # Czech "jakmile" is always tagged SCONJ (although one could also argue that it is a relative adverb of time).
        # In 55 cases it is attached as AuxC and in 1 case as Adv; but this 1 case is not different, it is an error.
        # Changing Adv to AuxC would normally also involve moving the conjunction between the subordinate predicate and
        # its parent, but we do not need to do that because our target style is UD and there both AuxC (mark) and Adv (advmod)
        # will be attached as children of the subordinate predicate.
        elsif(lc($form) eq 'jakmile' && $pos eq 'conj' && $deprel eq 'Adv')
        {
            $node->set_deprel('AuxC');
        }
        # In the Czech PDT, there is one occurrence of English "Devil ' s Hole", with the dependency AuxT(Devil, s).
        # Since "s" is not a reflexive pronoun, the convertor would convert the AuxT to compound:prt, which is not allowed in Czech.
        # Make it Atr instead. It will be converted to foreign.
        elsif($form eq 's' && $node->deprel() eq 'AuxT' && $node->parent()->form() eq 'Devil')
        {
            $node->set_deprel('Atr');
        }
        # In AnCora (ca+es), the MWE "10_per_cent" will have the lemma "10_%", which is a mismatch in number of elements.
        elsif($form =~ m/_(per_cent|por_ciento)$/i && $lemma =~ m/_%$/)
        {
            $lemma = lc($form);
            $node->set_lemma($lemma);
        }
    }
}



#------------------------------------------------------------------------------
# Relabel subordinate clauses. In the Croatian SETimes corpus, their predicates
# are labeled 'Pred', which translates as 'parataxis'. But we want to
# distinguish the various types of subordinate clauses instead.
#------------------------------------------------------------------------------
sub relabel_subordinate_clauses
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants();
    foreach my $node (@nodes)
    {
        my $deprel = $node->deprel();
        if($deprel eq 'parataxis')
        {
            my $parent = $node->parent();
            next if($parent->is_root());
            my @marks = grep {$_->deprel() eq 'mark'} ($node->children());
            # We do not know what to do when there is no mark. Perhaps it is indeed a parataxis?
            next if(scalar(@marks)==0);
            # Relative clauses modify a noun. They substitute for an adjective.
            if($parent->is_noun())
            {
                $node->set_deprel('acl');
                foreach my $mark (@marks)
                {
                    # The Croatian treebank analyzes both subordinating conjunctions and relative pronouns
                    # the same way. We want to separate them again. Pronouns should not be labeled 'mark'.
                    # They probably fill a slot in the frame of the subordinate verb: 'nsubj', 'obj' etc.
                    if($mark->is_pronoun() && $mark->is_noun())
                    {
                        my $case = $mark->iset()->case();
                        if($case eq 'nom' || $case eq '')
                        {
                            $mark->set_deprel('nsubj');
                        }
                        else
                        {
                            $mark->set_deprel('obj');
                        }
                    }
                }
            }
            # Complement clauses depend on a verb that requires them as argument.
            # Examples: he says that..., he believes that..., he hopes that...
            elsif(any {my $l = $_->lemma(); defined($l) && $l eq 'da'} (@marks))
            {
                $node->set_deprel('ccomp');
            }
            # Adverbial phrases modify a verb. They substitute for an adverb.
            # Example: ... if he passes the exam.
            else
            {
                $node->set_deprel('advcl');
            }
        }
    }
}



1;

=over

=item Treex::Block::HamleDT::Udep

Converts dependency trees from the HamleDT/Prague style to the Universal
Dependencies. This block is experimental. In the future, it may be split into
smaller blocks, moved elsewhere in the inheritance hierarchy or otherwise
rewritten. It is also possible (actually quite likely) that the current
Harmonize* blocks will be modified to directly produce Universal Dependencies,
which will become our new default central annotation style.

=back

=head1 AUTHORS

Daniel Zeman <zeman@ufal.mff.cuni.cz>

=head1 COPYRIGHT AND LICENSE

Copyright © 2014-2016 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
