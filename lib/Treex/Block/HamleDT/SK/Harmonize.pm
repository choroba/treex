package Treex::Block::HamleDT::SK::Harmonize;
use Moose;
use Treex::Core::Common;
use utf8;
extends 'Treex::Block::HamleDT::HarmonizePDT';

has iset_driver =>
(
    is            => 'ro',
    isa           => 'Str',
    required      => 1,
    default       => 'sk::snk',
    documentation => 'Which interset driver should be used to decode tags in this treebank? '.
                     'Lowercase, language code :: treebank code, e.g. "cs::pdt".'
);



#------------------------------------------------------------------------------
# Reads the Slovak tree, converts morphosyntactic tags and dependency relation
# labels, and transforms tree to adhere to the HamleDT guidelines.
#------------------------------------------------------------------------------
sub process_zone
{
    my $self = shift;
    my $zone = shift;
    my $root = $self->SUPER::process_zone($zone);
}



#------------------------------------------------------------------------------
# Different source treebanks may use different attributes to store information
# needed by Interset drivers to decode the Interset feature values. By default,
# the CoNLL 2006 fields CPOS, POS and FEAT are concatenated and used as the
# input tag. If the morphosyntactic information is stored elsewhere (e.g. in
# the tag attribute), the Harmonize block of the respective treebank should
# redefine this method. Note that even CoNLL 2009 differs from CoNLL 2006.
#------------------------------------------------------------------------------
sub get_input_tag_for_interset
{
    my $self   = shift;
    my $node   = shift;
    return $node->tag();
}



#------------------------------------------------------------------------------
# Adds Interset features that cannot be decoded from the PDT tags but they can
# be inferred from lemmas and word forms.
#------------------------------------------------------------------------------
sub fix_morphology
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants();
    foreach my $node (@nodes)
    {
        my $form = $node->form();
        my $lemma = $node->lemma();
        my $iset = $node->iset();
        # Fix Interset features of pronominal words.
        if($node->is_pronominal())
        {
            ###!!! We also need to handle fusions: do_on na_on na_ono naň oň po_on pre_on preň u_on za_on
            if($lemma =~ m/^(ja|ty|on|ona|ono|my|vy)$/)
            {
                $iset->set('pos', 'noun');
                $iset->set('prontype', 'prs');
            }
            elsif($lemma =~ m/^(seba|si|sa)$/)
            {
                $iset->set('pos', 'noun');
                $iset->set('prontype', 'prs');
                $iset->set('reflex', 'reflex');
            }
            elsif($lemma =~ m/^(môj|tvoj)$/)
            {
                $iset->set('pos', 'adj');
                $iset->set('prontype', 'prs');
                $iset->set('poss', 'poss');
                $iset->set('possnumber', 'sing');
            }
            elsif($lemma =~ m/^(jeho)$/)
            {
                $iset->set('pos', 'adj');
                $iset->set('prontype', 'prs');
                $iset->set('poss', 'poss');
                $iset->set('possnumber', 'sing');
                $iset->set('possgender', 'masc|neut');
            }
            elsif($lemma =~ m/^(jej)$/)
            {
                $iset->set('pos', 'adj');
                $iset->set('prontype', 'prs');
                $iset->set('poss', 'poss');
                $iset->set('possnumber', 'sing');
                $iset->set('possgender', 'fem');
            }
            elsif($lemma =~ m/^(náš|váš|ich)$/)
            {
                $iset->set('pos', 'adj');
                $iset->set('prontype', 'prs');
                $iset->set('poss', 'poss');
                $iset->set('possnumber', 'plur');
            }
            elsif($lemma =~ m/^(svoj)$/)
            {
                $iset->set('pos', 'adj');
                $iset->set('prontype', 'prs');
                $iset->set('poss', 'poss');
                $iset->set('reflex', 'reflex');
            }
            # Unlike in Czech, there are separate lemmas for each gender (ten-ta-to).
            # Neuter singular is very likely to act more like pronoun than like determiner but we currently keep it consistent with Czech and Slovenian, i.e. all demonstratives are DET.
            elsif($lemma =~ m/^(ta|taktýto|takéto|taký|takýto|tamten|ten|tento|to|toto|tá|táto|týmto|onaký)$/)
            {
                $iset->set('pos', 'adj');
                $iset->set('prontype', 'dem');
            }
            elsif($lemma =~ m/^(kto|ktože|čo|čože)$/)
            {
                $iset->set('pos', 'noun');
                $iset->set('prontype', 'int|rel');
            }
            elsif($lemma =~ m/^((nie|málo|všeli)(kto|čo)|(kto|čo)(si|koľvek))$/)
            {
                $iset->set('pos', 'noun');
                $iset->set('prontype', 'ind');
            }
            elsif($lemma =~ m/^(všetko)$/)
            {
                $iset->set('pos', 'noun');
                $iset->set('prontype', 'tot');
            }
            elsif($lemma =~ m/^(nik|nikto|nič)$/)
            {
                $iset->set('pos', 'noun');
                $iset->set('prontype', 'neg');
            }
            elsif($lemma =~ m/^(aký|ktorý)$/)
            {
                $iset->set('pos', 'adj');
                $iset->set('prontype', 'int|rel');
            }
            elsif($lemma =~ m/^(čí)$/)
            {
                $iset->set('pos', 'adj');
                $iset->set('prontype', 'int|rel');
                $iset->set('poss', 'poss');
            }
            elsif($lemma =~ m/^((da|kade|ne|všeli)(jaký)|(hoci|nie|poda)(ktorý)|iný|istý|všakovaký|(aký|ktorý)(si|koľvek))$/)
            {
                $iset->set('pos', 'adj');
                $iset->set('prontype', 'ind');
            }
            elsif($lemma =~ m/^čí(si|koľvek)$/)
            {
                $iset->set('pos', 'adj');
                $iset->set('prontype', 'ind');
                $iset->set('poss', 'poss');
            }
            elsif($lemma =~ m/^(sám|samý)$/)
            {
                $iset->set('pos', 'adj');
                $iset->set('prontype', 'emp');
            }
            elsif($lemma =~ m/^(každý|všetok)$/)
            {
                $iset->set('pos', 'adj');
                $iset->set('prontype', 'tot');
            }
            elsif($lemma =~ m/^(nijaký|žiaden|žiadny)$/)
            {
                $iset->set('pos', 'adj');
                $iset->set('prontype', 'neg');
            }
            # Pronominal quantifiers (numerals).
            elsif($lemma eq 'koľko')
            {
                $iset->set('pos', 'adj');
                $iset->set('prontype', 'int|rel');
                $iset->set('numtype', 'card');
            }
            elsif($lemma eq 'koľkokrát')
            {
                $iset->set('pos', 'adv');
                $iset->set('prontype', 'int|rel');
                $iset->set('numtype', 'mult');
            }
            elsif($lemma eq 'toľko')
            {
                $iset->set('pos', 'adj');
                $iset->set('prontype', 'dem');
                $iset->set('numtype', 'card');
            }
            elsif($lemma eq 'toľkokrát')
            {
                $iset->set('pos', 'adj');
                $iset->set('prontype', 'dem');
                $iset->set('numtype', 'mult');
            }
            elsif($lemma =~ m/^nieko[ľl]k[oý]$/)
            {
                $iset->set('pos', 'adj');
                $iset->set('prontype', 'ind');
                $iset->set('numtype', 'card');
            }
            elsif($lemma =~ m/^(niekoľko|veľa)krát$/)
            {
                $iset->set('pos', 'adj');
                $iset->set('prontype', 'ind');
                $iset->set('numtype', 'mult');
            }
            # Pronominal adverbs.
            elsif($lemma =~ m/^(ako|kadiaľ|kam|kamže|kde|kdeby|kedy|odkedy|odkiaľ|prečo)$/)
            {
                $iset->set('pos', 'adv');
                $iset->set('prontype', 'int|rel');
            }
            elsif($lemma =~ m/^(nejako?|(nie|bohvie|daj|ktovie|málo)(ako|kde|kedy)|inak|inde|inokade|inokedy|ináč|(ako|kadiaľ|kam|kde|kdeby|kedy|odkedy|odkiaľ)(si|koľvek))$/)
            {
                $iset->set('pos', 'adv');
                $iset->set('prontype', 'ind');
            }
            elsif($lemma =~ m/^(dosiaľ|dovtedy|natoľko|odtiaľ|odvtedy|onak|preto|sem|stadiaľ|tade|tadiaľ|tadiaľto|tak|takisto|takto|tam|tamhľa|tu|už|vtedy|zatiaľ)$/)
            {
                $iset->set('pos', 'adv');
                $iset->set('prontype', 'dem');
            }
            elsif($lemma =~ m/^(všade|všelijako|vždy)$/)
            {
                $iset->set('pos', 'adv');
                $iset->set('prontype', 'tot');
            }
            elsif($lemma =~ m/^(nijako|nikam|nikde|nikdy)$/)
            {
                $iset->set('pos', 'adv');
                $iset->set('prontype', 'neg');
            }
            # Now that we know personal (and possessive personal) pronouns (and determiners), we can mark their person value.
            if($lemma =~ m/^(ja|my|môj|náš)$/)
            {
                $iset->set('person', 1);
            }
            elsif($lemma =~ m/^(ty|vy|tvoj|váš)$/)
            {
                $iset->set('person', 2);
            }
            elsif($lemma =~ m/^(on|ona|ono|jeho|jej|ich)$/)
            {
                $iset->set('person', 3);
            }
        }
        # Ordinal and multiplicative numerals must be distinguished from cardinals.
        if($node->is_numeral())
        {
            # The following ordinal numeral lemmas have been observed in the corpus:
            # desiaty, deviaty, deväťdesiaty, druhý, dvadsiaty, dvanásty, jedenásty,
            # osemdesiaty, piaty, posledný, prvá, prvý, sedemdesiaty, siedmy,
            # tretí, tridsiaty, trinásty, tristý, ôsmy, šesťdesiaty, šiesty, štvrtý, štvrý
            if($lemma =~ m/(prvý|druhý|tretí|štvrtý|piaty|šiesty|siedmy|ôsmy|deviaty|siaty|sty|stý|posledný)$/i)
            {
                $iset->set('pos', 'adj');
                $iset->set('numtype', 'ord');
            }
            elsif($lemma =~ m/(jedinký|jediný|dvojaký|dvojitý|štvrý|násobný|mnohoraký|mnohý|viacerý|ostatný)$/i)
            {
                $iset->set('pos', 'adj');
                $iset->set('numtype', 'mult');
            }
            elsif($lemma =~ m/(krát|dvojako|raz|neraz)$/i)
            {
                $iset->set('pos', 'adv');
                $iset->set('numtype', 'mult');
            }
            elsif($lemma =~ m/dvadsiatka/i)
            {
                $iset->set('pos', 'noun');
            }
        }
        if($node->is_verb())
        {
            # Negation of verbs is treated as derivational morphology in the Slovak National Corpus.
            # We have to merge negative verbs with their affirmative counterparts.
            my $original_polarity = $node->iset()->polarity();
            if($lemma =~ m/^ne./i && $lemma !~ m/^(nechať|nechávať|nenávidieť|nenávidený)$/i)
            {
                $lemma =~ s/^ne//i;
                $node->set_lemma($lemma);
                $iset->set('polarity', 'neg');
            }
            # In some cases the original annotation was OK: affirmative lemma of a negative form, negative polarity set.
            # Make sure we do not rewrite it now!
            # It does not make sense to mark polarity for "by". All other forms will have it marked.
            elsif($original_polarity ne 'neg' && !$node->is_conditional())
            {
                $iset->set('polarity', 'pos');
            }
            # SNC has a dedicated POS tag ('G*') for participles, i.e. they are neither verbs nor adjectives there.
            # Interset converts participles to verbs. However, we want only l-participles to be verbs.
            # We can distinguish them by lemma: l-participles have the infinitive (zabil => zabiť), other participles have
            # masculine nominative form of the participle (obkľúčený => obkľúčený, žijúcu => žijúci).
            # Edit: Unfortunately, sometimes an l-participle has a lemma other than the infinitive, hence we should look at the form as well.
            if($node->is_participle())
            {
                #if($lemma !~ m/ť$/)
                if($form !~ m/l[aoiy]?$/i)
                {
                    $iset->set('pos', 'adj');
                }
                # We do not annotate person with Slavic participles because it is not expressed morphologically.
                # However, the l-participles in Slovak seem to have the person feature.
                $iset->clear('person');
            }
        }
        # Distinguish coordinating and subordinating conjunctions.
        if($node->is_conjunction())
        {
            if($lemma =~ m/^(a|aj|ale|alebo|ani|avšak|ba|buď|i|jednak|lebo|len|lenže|nielen|no|predsa|preto|pritom|pričom|prv|síce|tak|takže|teda|to|veď|však|zato|či|čiže)$/)
            {
                $node->iset()->set('conjtype', 'coor');
            }
            else # aby ak ako akoby akože akže až hoci ibaže keby keď keďže kým nech než pokiaľ pokým pretože tým čo čím že
            {
                $node->iset()->set('conjtype', 'sub');
            }
        }
    }
}



#------------------------------------------------------------------------------
# Convert dependency relation labels.
# http://ufal.mff.cuni.cz/pdt2.0/doc/manuals/cz/a-layer/html/ch03s02.html
#------------------------------------------------------------------------------
sub convert_deprels
{
    my $self  = shift;
    my $root  = shift;
    my @nodes = $root->get_descendants();
    # Make sure that the dependency relation label is in the deprel attribute and not somewhere else.
    foreach my $node (@nodes)
    {
        ###!!! We need a well-defined way of specifying where to take the source label.
        ###!!! Currently we try three possible sources with defined priority (if one
        ###!!! value is defined, the other will not be checked).
        my $deprel = $node->deprel();
        $deprel = $node->afun() if(!defined($deprel));
        $deprel = $node->conll_deprel() if(!defined($deprel));
        $deprel = 'NR' if(!defined($deprel));
        $node->set_deprel($deprel);
    }
    # Coordination of prepositional phrases or subordinate clauses:
    # In PDT, is_member is set at the node that bears the real deprel. It is not set at the AuxP/AuxC node.
    # In HamleDT (and in Treex in general), is_member is set directly at the child of the coordination head (preposition or not).
    $self->pdt_to_treex_is_member_conversion($root);
    # Try to fix annotation inconsistencies around coordination.
    foreach my $node (@nodes)
    {
        if($node->is_member())
        {
            my $parent = $node->parent();
            if(!$parent->deprel() =~ m/^(Coord|Apos)$/)
            {
                if($parent->is_conjunction() || $parent->form() && $parent->form() =~ m/^(ani|,|;|:|-+)$/)
                {
                    $parent->set_deprel('Coord');
                }
                else
                {
                    $node->set_is_member(undef);
                }
            }
        }
        # combined deprels (AtrAtr, AtrAdv, AdvAtr, AtrObj, ObjAtr) -> Atr
        if($node->deprel() =~ m/^(AtrAtr)|(AtrAdv)|(AdvAtr)|(AtrObj)|(ObjAtr)/)
        {
            $node->set_deprel('Atr');
        }
        # negation (can be either AuxY or AuxZ in the input)
        if ($node->deprel() =~ m/^Aux[YZ]$/ && $node->form() =~ m/^nie$/i)
        {
            $node->set_deprel('Neg');
        }
    }
    # Now the above conversion could be trigerred at new places.
    # (But we have to do it above as well, otherwise the correction of coordination inconsistencies would be less successful.)
    $self->pdt_to_treex_is_member_conversion($root);
    # Guess deprels that the annotators have not assigned.
    foreach my $node (@nodes)
    {
        if($node->deprel() eq 'NR')
        {
            $node->set_deprel($self->guess_deprel($node));
        }
    }
}



#------------------------------------------------------------------------------
# Fixes a few known annotation errors that appear in the data.
# This method will be called right after converting the deprels to the
# harmonized label set, but before any tree transformations.
#------------------------------------------------------------------------------
sub fix_annotation_errors
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants({ordered => 1});
    foreach my $node (@nodes)
    {
        my $parent = $node->parent();
        my @children = $node->children();
        # Deficient sentential coordination ("And" at the beginning of the sentence):
        # There are hundreds of cases where the conjunction is labeled Coord but the child has not is_member set.
        if($node->deprel() =~ m/^(Coord|Apos)$/ && !grep {$_->is_member()} (@children))
        {
            # If the node is leaf we cannot hope to find any conjuncts.
            # The same holds if the node is not leaf but its children are not eligible for conjuncts.
            if(scalar(grep {$_->deprel() !~ m/^Aux[GXY]$/} (@children))==0)
            {
                if($node->form() eq ',')
                {
                    $node->set_deprel('AuxX');
                }
                elsif($node->is_punctuation())
                {
                    $node->set_deprel('AuxG');
                }
                else
                {
                    # It is not punctuation, thus it is a word or a number.
                    # As it was labeled Coord, let us assume that it is an extra conjunction in coordination that is headed by another conjunction.
                    $node->set_deprel('AuxY');
                }
            }
            # There are possible conjuncts and we must identify them.
            else
            {
                $self->identify_coap_members($node);
            }
        }
        # Verb "je" labeled AuxX.
        elsif($node->form() eq 'je' && $node->deprel() eq 'AuxX' && $parent->deprel() eq 'Coord')
        {
            $node->set_deprel('Pred');
            $node->set_is_member(1);
        }
        # Conjunction "akoby" labeled AuxY ("Lenže akoby sa díval na...")
        elsif($node->form() eq 'akoby' && $node->deprel() eq 'AuxY' && $parent->deprel() eq 'Coord')
        {
            $node->set_deprel('AuxC');
            $node->set_is_member(1);
        }
        # Colon at sentence end, labeled Apos although there are no children.
        elsif($node->form() eq ':' && $node->deprel() eq 'Apos' && $node->is_leaf())
        {
            $node->set_deprel('AuxG');
        }
        # Colon at sentence end, subordinate clause attached to it instead of the verb.
        elsif($node->form() eq 'a' && !$parent->is_root() && $parent->form() eq ':' && !$parent->get_next_node() && !$parent->parent()->is_root() && $parent->parent()->is_verb())
        {
            my $verb = $parent->parent();
            $node->set_parent($verb);
            $node->set_is_member(undef);
        }
    }
}



#------------------------------------------------------------------------------
# The Slovak Treebank suffers from several hundred unassigned syntactic tags.
# This function can be used to guess them based on morphosyntactic features of
# parent and child.
#------------------------------------------------------------------------------
sub guess_deprel
{
    my $self = shift;
    my $node = shift;
    my $parent = $node->parent(); ###!!! eparents? Akorát že ty závisí na správných deprelech a rodič zatím taky nemusí mít správný deprel.
    my $pos = $node->iset()->pos();
    my $ppos = $parent->iset()->pos();
    my $deprel = 'NR';
    if($parent->is_root())
    {
        if($pos eq 'verb')
        {
            $deprel = 'Pred';
        }
        elsif($node->form() eq 'ale' && grep {$_->deprel() !~ m/^(Aux[GXY])$/} ($node->children()))
        {
            $deprel = 'Coord';
            foreach my $child ($node->children())
            {
                if($child->deprel() !~ m/^Aux[GXY]$/)
                {
                    $child->set_is_member(1);
                }
                else
                {
                    $child->set_is_member(undef);
                }
            }
        }
    }
    # We may not be able to recognize coordination if parent's label is yet to be guessed.
    # But if we know there is a Coord, why not use it?
    elsif($parent->deprel() eq 'Coord')
    {
        if($node->is_leaf() && $pos eq 'punc')
        {
            if($node->form() eq ',')
            {
                $deprel = 'AuxX';
            }
            else
            {
                $deprel = 'AuxG';
            }
        }
        else # probably conjunct
        {
            ###!!! We should look at the parent of the coordination and guess the function of the coordination.
            ###!!! Or figure out functions of other conjuncts if they have them.
            $deprel = 'ExD';
            $node->set_is_member(1);
        }
    }
    # Preposition is always AuxP. The real function is tagged at its argument.
    elsif($pos eq 'adp')
    {
        $deprel = 'AuxP';
    }
    elsif($parent->form() eq 'než')
    {
        # větší než já
        # V PDT se podobné fráze analyzují jako elipsa ("má větší příjem než [mám] já").
        $deprel = 'ExD';
    }
    elsif($parent->form() eq 'ako')
    {
        # cien známych ako Kristián
        # V PDT se fráze se spojkou "jako" analyzují jako doplněk. Ovšem "jako" tam visí až na doplňku, čímž se liší od jiných výskytů podřadících spojek a předložek.
        $deprel = 'Atv';
    }
    elsif($parent->form() eq 'že')
    {
        $deprel = 'Obj';
    }
    elsif($ppos eq 'noun')
    {
        $deprel = 'Atr';
    }
    elsif($node->is_foreign())
    {
        $deprel = 'Atr';
    }
    elsif($ppos eq 'adj' && ($pos eq 'adj' || $node->iset()->prontype() ne ''))
    {
        $deprel = 'Atr';
    }
    elsif($ppos eq 'num' && $pos eq 'noun') # example: viacero stredísk
    {
        $deprel = 'Atr';
    }
    elsif($ppos eq 'verb')
    {
        my $case = $node->iset()->case();
        if($node->form() eq 'nie')
        {
            ###!!! This should be Neg but we should change it in all nodes, not just in those where we guess labels.
            $deprel = 'Adv';
        }
        elsif($pos eq 'noun')
        {
            if($case eq 'nom')
            {
                $deprel = 'Sb';
            }
            else
            {
                $deprel = 'Obj';
            }
        }
        elsif($pos eq 'adj' && $case eq 'nom' && $parent->lemma() =~ m/^(ne)?byť$/)
        {
            $deprel = 'Pnom';
        }
        elsif($pos eq 'verb') # especially infinitive
        {
            $deprel = 'Obj';
        }
        elsif($pos eq 'adv')
        {
            $deprel = 'Adv';
        }
        elsif($node->form() =~ m/^ak$/i)
        {
            $deprel = 'AuxC';
        }
    }
    return $deprel;
}



1;

=over

=item Treex::Block::HamleDT::SK::Harmonize

Converts SNK (Slovak National Corpus) trees to the HamleDT style. Currently
it only involves conversion of the morphological tags (and Interset decoding).

=back

=cut

# Copyright 2014, 2015 Dan Zeman <zeman@ufal.mff.cuni.cz>

# This file is distributed under the GNU General Public License v2. See $TMT_ROOT/README.
