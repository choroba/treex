package Treex::Block::HamleDT::JA::Harmonize;
use utf8;
use Moose;
use List::Util qw(first);
use Treex::Core::Common;
use Treex::Tool::PhraseBuilder::MoscowToPrague;
extends 'Treex::Block::HamleDT::Harmonize';



has iset_driver =>
(
    is            => 'ro',
    isa           => 'Str',
    required      => 1,
    default       => 'ja::conll',
    documentation => 'Which interset driver should be used to decode tags in this treebank? '.
                     'Lowercase, language code :: treebank code, e.g. "cs::pdt".'
);



#------------------------------------------------------------------------------
# Reads the Japanese CoNLL trees, converts morphosyntactic tags to the positional
# tagset and transforms the tree to adhere to PDT guidelines.
#------------------------------------------------------------------------------
sub process_zone
{
    my $self   = shift;
    my $zone   = shift;
    my $a_root = $self->SUPER::process_zone($zone);
    # Phrase-based implementation of tree transformations (5.3.2016).
    my $builder = new Treex::Tool::PhraseBuilder::MoscowToPrague
    (
        'prep_is_head'           => 1,
        'coordination_head_rule' => 'last_coordinator'
    );
    my $phrase = $builder->build($root);
    $phrase->project_dependencies();
    $self->attach_final_punctuation_to_root($a_root);
    $self->check_deprels($a_root);
}



#------------------------------------------------------------------------------
# Convert dependency relation labels.
# /net/data/conll/2006/ja/doc/report-240-00.ps
# http://ufal.mff.cuni.cz/pdt2.0/doc/manuals/cz/a-layer/html/ch03s02.html
#------------------------------------------------------------------------------
sub convert_deprels
{
    my $self = shift;
    my $root = shift;
    for my $node ($root->get_descendants())
    {
        ###!!! We need a well-defined way of specifying where to take the source label.
        ###!!! Currently we try three possible sources with defined priority (if one
        ###!!! value is defined, the other will not be checked).
        my $deprel = $node->deprel();
        $deprel = $node->afun() if(!defined($deprel));
        $deprel = $node->conll_deprel() if(!defined($deprel));
        $deprel = 'NR' if(!defined($deprel));
        my $form = $node->form();
        my $conll_cpos = $node->conll_cpos();
        my $conll_pos = $node->conll_pos();
        my $pos = $node->get_iset('pos');
        # my $subpos = $node->get_iset('subpos'); # feature deprecated
        my $parent = $node->get_parent();
        my $ppos = $parent->get_iset('pos');
        # my $psubpos = $parent->get_iset('subpos'); # feature deprecated
        my @children = $node->get_children({ordered => 1});
        # children of the technical root
        if ($deprel eq 'ROOT')
        {
            # "clean" predicate
            if ($pos eq 'verb')
            {
                $deprel = 'Pred';
            }
            # postposition/particle as a head - but we do not want
            # to assign AuxP now; later we will pass the label to the child
            elsif ($node->get_iset('adpostype') eq 'post' or $pos eq 'part')
            {
                $deprel = 'Pred';
            }
            # coordinating conjunction/particle (Pconj)
            elsif ($node->get_iset('conjtype') eq 'coor')
            {
                $deprel = 'Pred';
                $node->wild()->{coordinator} = 1;
            }
            elsif ($pos eq 'punc')
            {
                if ($node->get_iset('punctype') =~ m/^(peri|qest)$/)
                {
                    $deprel = 'AuxK';
                }
            }
            else
            {
                $deprel = 'ExD';
            }
        }

        # Punctuation
        elsif ($deprel eq 'PUNCT')
        {
            my $punctype = $node->get_iset('punctype');
            if ($punctype eq 'comm')
            {
                $deprel = 'AuxX';
            }
            elsif ($punctype =~ m/^(peri|qest|excl)$/)
            {
                $deprel = 'AuxK';
            }
            else
            {
                $deprel = 'AuxG';
            }
        }

        # Subject
        elsif ($deprel eq 'SBJ')
        {
            $deprel = 'Sb';
            #if ($subpos eq 'coor') {
            #    $node->wild()->{coordinator} = 1;
            #}
        }

        # Complement
        # obligatory element with respect to the head incl. bound forms
        # ("nominal suffixes, postpositions, formal nouns, auxiliary verbs and
        # so on") and predicate-argument structures
        elsif ($deprel eq 'COMP')
        {
            if ($ppos eq 'adp')
            {
                $deprel = 'PrepArg';
            }
            elsif ($ppos eq 'part')
            {
                $deprel = 'SubArg';
            }
            #elsif ($psubpos eq 'coor') {
            #    $deprel = 'CoordArg';
            #    $node->wild()->{conjunct} = 1;
            #}
            elsif ($ppos eq 'verb')
            {
                if ($parent->get_iset('verbtype') eq 'cop')
                {
                    $deprel = 'Pnom';
                }
                # just a heuristic
                elsif ($pos eq 'adv')
                {
                    $deprel = 'Adv';
                }
                else
                {
                    $deprel = 'Obj';
                }
            }
            else
            {
                $deprel = 'Atr';
            }
        }
        # Adjunct
        # any left-hand constituent that is not a complement/subject
        elsif ($deprel eq 'ADJ')
        {
            if ($pos eq 'conj')
            {
                $deprel = 'Coord';
                $node->wild()->{coordinator} = 1;
                $parent->wild()->{conjunct} = 1;
            }
            # if the parent is preposition, this node must be rehanged onto the preposition complement
            elsif ($parent->conll_pos =~ m/^(Nsf|P|PQ|Pacc|Pfoc|Pgen|Pnom)$/)
            {
                $deprel = 'Atr';
                # find the complement among the siblings (preferring the ones to the right);
                my @siblings = ($node->get_siblings({following_only=>1}), $node->get_siblings({preceding_only=>1}));
                my $new_parent = ( first { $_->conll_deprel eq 'COMP' } @siblings ) || $parent;
                $node->set_parent($new_parent);
            }
            elsif ($ppos =~ m/^(noun|num)$/)
            {
                $deprel = 'Atr';
            }
            # daitai kono youna = だいたい この ような
            # daitai = 大体 = substantially, approximately
            # kono = この = this
            # youna = ような = like, similar-to (adjectival postposition)
            elsif ($ppos =~ m/^(verb|adj|adv|adp)$/)
            {
                $deprel = 'Adv';
            }
            # Topicalized adjuncts with the marker "wa" attached to the main clause.
            # Example: kyou kite itadaita no wa, ...
            elsif (scalar(@children) >= 1 && $children[-1]->form() eq 'wa')
            {
                ###!!! There is not a better label at the moment but we may want to create a special language-specific label for this in future.
                ###!!! We may also want to treat "wa" as postposition and reattach it to head the adjunct.
                $deprel = 'Adv';
            }
            elsif ($node->get_iset('advtype') eq 'tim')
            {
                $deprel = 'Adv';
            }
            elsif ($node->form() eq 'kedo' && $parent->form() eq 'kedo')
            {
                $deprel = 'Adv';
            }
            elsif ($ppos eq 'part')
            {
                $deprel = 'Adv';
            }
            else {
                $deprel = 'NR';
                print STDERR ($node->get_address, "\t",
                              "Unrecognized $conll_pos ADJ under ", $parent->conll_pos, "\n");
            }
        }

        # Marker
        elsif ($deprel eq 'MRK')
        {
            # topicalizers and focalizers
            if ($conll_pos eq 'Pfoc')
            { ###!!! We must not depend on the original value of $conll_pos because it has been replaced by now.
                $deprel = 'AuxZ';
            }
            # particles for expressing attitude/empathy, or turning the phrase
            # into a question
            elsif ($pos eq 'part' && $form =~ m/^(ne|ka|yo|mono|kke|na|kana|kashira|shi|naa|wa|moN)$/)
            {
                $deprel = 'AuxO';
            }
            # postpositions after adverbs with no syntactic but a rhetorical function
            elsif ($conll_pos eq 'P' and $ppos eq 'adv')
            {
                $deprel = 'AuxO';
            }
            # coordination marker
            elsif ($node->get_iset('conjtype') eq 'coor' or $pos eq 'conj')
            {
                $deprel = 'Coord';
                $node->wild()->{coordinator} = 1;
                $parent->wild()->{conjunct} = 1;
            }
            # two-word conjunction "narabi ni" = ならびに = 並びに = and (also); both ... and; as well as
            # shashiNka = しゃしんか = 写真家 = photographer
            # Example: doitsu no amerikajiN shashiNka narabi ni amerika no doitsujiN shashiNka
            elsif ($form eq 'ni' && scalar(@children)==1 && $children[0]->form() eq 'narabi')
            {
                ###!!! The current detection of coordination will probably fail at this.
                $deprel = 'AuxY'; # this is intended to be later shifted one level down
                $node->wild()->{coordinator} = 1; # this is intended to survive here
                $parent->wild()->{conjunct} = 1;
            }
            # douka = どうか = please
            elsif ($form eq 'douka')
            {
                $deprel = 'ExD';
            }
            # atari = あたり: around
            # juuninichi juusaNnichi atari de = around the twelfth, thirteenth
            elsif ($form eq 'atari')
            {
                $deprel = 'AuxY';
            }
            elsif ($pos eq 'adp' || $node->form() =~ m/^(ato|no)$/)
            {
                $deprel = 'AuxP';
            }
            else
            {
                $deprel = 'NR';
                print STDERR ($node->get_address, "\t",
                              "Unrecognized $conll_pos MRK under ", $parent->conll_pos, "\n");
            }
        }

        # Co-head
        # "listing of items, coordinations, and compositional expressions"
        # compositional expressions: date & time, full name, from-to expressions
        elsif ($deprel eq 'HD')
        {
            # coordinations
            my @siblings = $node->get_siblings();
            if ( first {$_->get_iset('pos') eq 'conj'} @siblings )
            {
                $deprel = 'CoordArg';
                $node->wild()->{conjunct} = 1;
            }
            # names
            elsif ($node->get_iset('nountype') eq 'prop' and $parent->get_iset('nountype') eq 'prop')
            {
                $deprel = 'Atr';
            }
            # date and time
            elsif ($node->get_iset('advtype') eq 'tim' and $parent->get_iset('advtype') eq 'tim')
            {
                $deprel = 'Atr';
            }
            # others mostly also qualify for Atr, e.g.
            # 寒九十時で = kaNkuu juuji de = ninth-day-of-cold-season ten-o-clock at
            # 一日版 = ichinichi haN = first-day-of-month edition
            elsif ($ppos =~ m/^(noun|num)$/ || $parent->get_iset('advtype') eq 'tim')
            {
                $deprel = 'Atr';
            }
            elsif ($pos eq 'adv' && $ppos eq 'adv')
            {
                $deprel = 'Adv';
            }
            # juuichiji = 十一時 = 11 hours (CDtime/HD)
            # yoNjuppuN = 四十分 = よんじゅっぷん = 40 minutes (CDtime/COMP)
            # hatsu (Nsf/HD) = 発? = departing ... značka Nsf znamená "noun suffix", takže není jasné, proč vlastně je z toho v Intersetu záložka. I když to asi může mít podobné chování.
            # In this case the "hatsu" was attached to another "hatsu", from "kaNsaikuukou hatsu" (location from which they departed).
            elsif ($pos eq 'adp' && $ppos eq 'adp')
            {
                $deprel = 'Atr';
            }
            # nanika = なにか = 何か = something (NN/HD)
            # koukuugaisha de kimetai toka
            # toka = とか = among other things (Pcnj/COMP)
            elsif ($pos eq 'noun' && $ppos =~ m/^(adp|conj)$/)
            {
                $deprel = 'Atr';
            }
            elsif ($ppos eq 'noun')
            {
                $deprel = 'Atr';
            }
            # yoru shichiji goro = lit. night seven-o-clock around
            elsif ($node->get_iset('advtype') eq 'tim' && $ppos eq 'adp')
            {
                ###!!! We should reshape the structure so that only one of the time specifications depends directly on the postposition.
                $deprel = 'Atr';
            }
            ###!!! Should this be coordination?
            # deNsha de iku ka hikouki de iku ka
            # naNji ni shuppatsu suru ka, chuuoueki ni naNji ni koreba ii ka
            elsif ($node->form() =~ m/^(ka|nari|toka)$/ && $parent->form() eq $node->form())
            {
                $deprel = 'Atr';
            }
            elsif ($node->form() eq 'ka' && $ppos eq 'verb')
            {
                $deprel = 'Adv';
            }
            # takaku mo nai hikuku mo nai
            elsif ($node->form() eq 'nai' && $parent->form() eq 'nai')
            {
                $deprel = 'Atr';
            }
            # yasui takai
            elsif ($pos eq 'adj' && $ppos eq 'adj')
            {
                $deprel = 'Atr';
            }
            # shoushou = しょうしょう = 少々 = just a minute
            elsif ($node->form() eq 'shoushou')
            {
                $deprel = 'Adv';
            }
            # yoroshikereba = よろしければ = if you please, if you don't mind
            elsif ($node->form() eq 'yoroshikereba')
            {
                $deprel = 'Adv';
            }
            elsif ($pos eq 'adv')
            {
                $deprel = 'Adv';
            }
            elsif ($conll_cpos =~ m/^P/)
            {
                $deprel = 'Adv';
            }
            # maireeji desu  toka oshokuji desu  toka nanika
            # NN       PVfin Pcnj VN       PVfin Pcnj NN
            # COMP     COMP  HD   COMP     COMP  HD   SBJ
            # まいれえじ です とか おしょくじ です とか なにか
            # マイレージ = mileage
            # お食事 = dining, restaurant
            # とか = among other things
            elsif ($ppos eq 'noun')
            {
                $deprel = 'Atr';
            }
            elsif ($pos eq 'verb' && $parent->form() eq 'ka')
            {
                $deprel = 'SubArg';
            }
            else {
                $deprel = 'NR';
                print STDERR $node->get_address, "\t", "Unrecognized $conll_pos HD under ", $parent->conll_pos, "\n";
            }
        }

        # Unspecified
        # numericals, speech errors, interjections
        elsif ($deprel eq '-') {
            $deprel = 'ExD';
        }

        # No other deprel is defined
        else {
            $deprel = 'NR';
            print STDERR $node->get_address, "\t", "Unrecognized deprel $deprel", "\n";
        }
        $node->set_deprel($deprel);
    }
}



#------------------------------------------------------------------------------
# Fixes a few known annotation errors and irregularities.
#------------------------------------------------------------------------------
sub fix_annotation_errors
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants({ordered => 1});
    foreach my $node (@nodes)
    {
        ###!!! DZ: Well, this is not really an annotation error but I am failing at the moment to solve it at the right place.
        if ($node->form() eq 'nanika')
        {
            my @children = $node->children();
            if (scalar(@children)==2 && $children[0]->form() eq 'toka' && $children[1]->form() eq 'toka')
            {
                # There are two conjuncts, each headed by its own coordinating postposition "toka" ("among other things").
                my @gc0 = $children[0]->children();
                my @gc1 = $children[1]->children();
                if (scalar(@gc0)==1 && scalar(@gc1)==1)
                {
                    my $toka0 = $children[0];
                    my $toka1 = $children[1];
                    my $gc0 = $gc0[0];
                    my $gc1 = $gc1[0];
                    $toka1->set_deprel('Coord');
                    $toka1->wild()->{conjunct} = undef;
                    $gc1->set_deprel('Atr');
                    $gc1->set_is_member(1);
                    $toka0->set_parent($toka1);
                    $toka0->set_deprel('AuxY');
                    $toka0->wild()->{conjunct} = undef;
                    $gc0->set_parent($toka1);
                    $gc0->set_deprel('Atr');
                    $gc0->set_is_member(1);
                }
            }
            elsif (scalar(@children)==0 && !$node->parent()->is_root() && $node->parent()->form() eq 'nanika')
            {
                $node->set_deprel('Atr');
                $node->wild()->{conjunct} = undef;
            }
        }
    }
}



1;

=over

=item Treex::Block::HamleDT::JA::Harmonize

Converts Japanese CoNLL treebank into PDT style treebank.

1. Morphological conversion             -> Yes

2. DEPREL conversion                    -> Yes

3. Structural conversion to match PDT   -> Yes


=back

=cut

# Copyright 2011 Loganathan Ramasamy <ramasamy@ufal.mff.cuni.cz>
# Copyright 2014 Jan Mašek <masek@ufal.mff.cuni.cz>
# Copyright 2011, 2014, 2015, 2016 Dan Zeman <zeman@ufal.mff.cuni.cz>
# This file is distributed under the GNU General Public License v2. See $TMT_ROOT/README.
