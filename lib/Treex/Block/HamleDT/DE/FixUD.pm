package Treex::Block::HamleDT::DE::FixUD;
use utf8;
use Moose;
use List::MoreUtils qw(any);
use Treex::Core::Common;
use Treex::Tool::PhraseBuilder::StanfordToUD;
extends 'Treex::Block::HamleDT::SplitFusedWords';



sub process_atree
{
    my $self = shift;
    my $root = shift;
    # Fix relations before morphology. The fixes depend only on UPOS tags, not on morphology (e.g. NOUN should not be attached as det).
    # And with better relations we will be more able to disambiguate morphological case and gender.
    # However, if there is anything to fix with UPOS (which was annotated manually in GSD),
    # do it before the relations.
    $self->fix_upos($root);
    $self->convert_deprels($root);
    $self->fix_morphology($root);
    $self->regenerate_upos($root);
}



#------------------------------------------------------------------------------
# Harmonizes certain UPOS tags, especially of closed classes. Unlike in FixUD
# blocks of some other languages, we do UPOS separately from features: UPOS
# before relations, features after relations. The reason is that UPOS are
# manual in German GSD while features are not, and we need the relations right
# in order to check e.g. some case values.
#------------------------------------------------------------------------------
sub fix_upos
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants();
    foreach my $node (@nodes)
    {
        my $lform = lc($node->form());
        my $lemma = $node->lemma();
        # German possessive "pronouns" (traditional term) are determiners in UD.
        # Checking the lemma is important (although it occasionally contains errors).
        # We want to avoid changin PRON with lemma 'ich', as well as VERB 'meinen', PROPN 'Meine' (village) etc.
        if($lform =~ m/^mein(er|es|em|en|e)?$/ && $lemma eq 'mein')
        {
            # The UPOS tag is PRON, DET, or even NOUN or PROPN. It should be DET.
            $node->iset()->add('pos' => 'adj', 'prontype' => 'prs', 'poss' => 'yes', 'person' => '1', 'possnumber' => 'sing');
        }
        elsif($lform =~ m/^dein(er|es|em|en|e)?$/ && $lemma eq 'dein')
        {
            $node->iset()->add('pos' => 'adj', 'prontype' => 'prs', 'poss' => 'yes', 'person' => '2', 'possnumber' => 'sing');
        }
        elsif($lform =~ m/^sein(er|es|em|en|e)?$/ && $lemma eq 'sein' && !$node->is_verb())
        {
            $node->iset()->add('pos' => 'adj', 'prontype' => 'prs', 'poss' => 'yes', 'person' => '3', 'possnumber' => 'sing', 'possgender' => 'masc|neut');
        }
        # "Ihr" can be a personal pronoun (2nd person plural) or a possessive determiner (3rd person feminine singular, or 3rd person plural, or honorific 2nd person).
        # If there is no agreement suffix, we cannot exclude the 2nd person plural pronoun, so we better don't change the POS category.
        # Note that the suffix is not optional here, unlike in "mein|dein|sein" above.
        elsif($lform =~ m/^ihr(er|es|em|en|e)$/ && ($lemma eq 'ihr' || $lemma eq 'Ihr|ihr'))
        {
            $node->iset()->add('pos' => 'adj', 'prontype' => 'prs', 'poss' => 'yes', 'person' => '3');
        }
        elsif($lform =~ m/^unser(er|es|em|e?n|e)?$/ && $lemma eq 'unser')
        {
            $node->iset()->add('pos' => 'adj', 'prontype' => 'prs', 'poss' => 'yes', 'person' => '1', 'possnumber' => 'plur');
        }
        elsif($lform =~ m/^euer(er|es|em|e?n|e)?$/ && $lemma eq 'euer')
        {
            $node->iset()->add('pos' => 'adj', 'prontype' => 'prs', 'poss' => 'yes', 'person' => '2', 'possnumber' => 'plur');
        }
    }
}



#------------------------------------------------------------------------------
# Converts dependency relations from UD v1 to v2.
#------------------------------------------------------------------------------
sub convert_deprels
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants();
    foreach my $node (@nodes)
    {
        my $parent = $node->parent();
        my $deprel = $node->deprel();
        # Fix inherently reflexive verbs.
        if($node->is_reflexive() && $self->is_inherently_reflexive_verb($parent->lemma()))
        {
            $node->set_deprel('expl:pv');
        }
        $self->fix_genitive_noun_modifiers($node);
        # "um" is attached to an infinitive as 'aux' instead of 'mark'.
        if($node->is_adposition() && $parent->is_verb() && $deprel =~ m/^aux(:|$)/)
        {
            $node->set_deprel('mark');
        }
        # Error: advmod(Optiker, keinem) should be det.
        if($parent->is_noun() && $node->deprel() =~ m/^advmod(:|$)/ && !$node->is_adverb())
        {
            my $upos = $node->tag();
            if($upos =~ m/^(PRON|NOUN|PROPN)$/)
            {
                $node->set_deprel('nmod');
            }
            elsif($upos eq 'ADJ')
            {
                $node->set_deprel('amod');
            }
            elsif($upos eq 'NUM')
            {
                $node->set_deprel('nummod');
            }
            elsif($upos eq 'DET')
            {
                $node->set_deprel('det');
            }
        }
        # Sometimes "kein" is attached to an adjective instead of the following noun.
        elsif($node->lemma() eq 'kein' && $parent->deprel() eq 'amod' && $node->deprel() =~ m/^advmod(:|$)/)
        {
            $parent = $parent->parent();
            $node->set_parent($parent);
            $deprel = 'det';
            $node->set_deprel($deprel);
        }
        # The pattern "etwas *es" (e.g. "etwas Besseres") is annotated inconsistently.
        # We make "etwas" always the head.
        if($node->lemma() eq 'etwas' && $node->parent()->ord() > $node->ord() && $node->parent()->form() =~ m/es$/i)
        {
            my $noun = $node->parent();
            $node->set_parent($noun->parent());
            $node->set_deprel($noun->deprel());
            $noun->set_parent($node);
            $noun->set_deprel('nmod');
            # Some instances have even a bad tag, such as PROPN or ADJ.
            $noun->set_tag('NOUN');
            $noun->iset()->set('pos' => 'noun');
            $noun->iset()->set('nountype' => 'com');
            $noun->iset()->set('gender' => 'neut');
            $noun->iset()->set('number' => 'sing');
            foreach my $child ($noun->children())
            {
                $child->set_parent($node);
            }
        }
        elsif($node->form() =~ m/es$/i && !$node->parent()->is_root() && $node->parent()->ord() < $node->ord() && $node->parent()->lemma() eq 'etwas')
        {
            $node->set_deprel('nmod');
            # Some instances have even a bad tag, such as PROPN or ADJ.
            $node->set_tag('NOUN');
            $node->iset()->set('pos' => 'noun');
            $node->iset()->set('nountype' => 'com');
            $node->iset()->set('gender' => 'neut');
            $node->iset()->set('number' => 'sing');
        }
        # In "auch wenn", "wenn" is 'mark' or 'cc' and "auch" is wrongly attached as 'advmod' to "wenn".
        if($node->deprel() =~ m/^advmod(:|$)/ && $parent->deprel() =~ m/^(cc|mark)(:|$)/)
        {
            $parent = $parent->parent();
            $node->set_parent($parent);
        }
        # Words like "Million" are tagged NOUN but attached as nummod. They have to be nmod.
        if($node->is_noun() && $node->deprel() eq 'nummod')
        {
            $deprel = 'nmod';
            $node->set_deprel($deprel);
        }
        # Phrases like "ein wenig", "ein paar", "zwei Jahre" are tagged NOUN but attached as advmod. They have to be obl or nmod.
        if($node->is_noun() && $node->deprel() =~ m/^advmod(:|$)/)
        {
            if($parent->is_noun())
            {
                $deprel = 'nmod';
            }
            else
            {
                $deprel = 'obl';
            }
            $node->set_deprel($deprel);
        }
        # Adjectives cannot be attached as det. They have to be amod.
        if($node->is_adjective() && !$node->is_pronominal() && $node->deprel() eq 'det')
        {
            $deprel = 'amod';
            $node->set_deprel($deprel);
        }
        # Nouns attached as cop should in fact be nsubj (they are subjects of nonverbal predicates in sentences where copula is missing).
        # The same holds for pronouns, such as "alles" ("everything"). In general pronouns can be copulas, but not in German.
        # (In Interset, is_noun() will catch pronouns as well.)
        # Another case is "ein" ("one") but it is tagged as determiner, not pronoun.
        if(($node->is_noun() || $node->lemma() eq 'ein') && $node->deprel() eq 'cop')
        {
            $deprel = 'nsubj';
            $node->set_deprel($deprel);
        }
        # Auxiliary verbs, adverbial modifiers and conjunctions are sometimes wrongly attached to the copula instead of the nominal predicate.
        $parent = $node->parent();
        if(defined($parent->deprel()) && $parent->deprel() =~ m/^(cop|aux)(:|$)/ && $deprel !~ m/^(conj|fixed|goeswith|reparandum|punct)$/)
        {
            $parent = $parent->parent();
            $node->set_parent($parent);
        }
        # Sometimes a prepositional phrase is still headed by the preposition.
        # The 'dep' child of 'case' often occurs at the end of a truncated sentence.
        if($node->deprel() =~ m/^(obj|obl|nmod|nsubj|xcomp|advmod|compound|det|amod|nummod|acl|dep)(:|$)/ && $parent->deprel() eq 'case')
        {
            if($parent->parent()->is_noun())
            {
                $deprel = 'nmod';
            }
            else
            {
                $deprel = 'obl';
            }
            my $preposition = $node->parent();
            $parent = $preposition->parent();
            $node->set_parent($parent);
            $node->set_deprel($deprel);
            $preposition->set_parent($node);
        }
        $self->fix_right_to_left_apposition($node);
        if($node->is_pronoun() && $node->deprel() eq 'advmod')
        {
            $deprel = 'obl';
            $node->set_deprel($deprel);
        }
        ###!!! Turn this off. The auxiliaries have been fixed already, and the
        ###!!! function may attempt to also "fix" some spurious cases.
        # $self->fix_auxiliary_verb($node);
    }
}



#------------------------------------------------------------------------------
# Fix auxiliary verb that should not be auxiliary.
#------------------------------------------------------------------------------
sub fix_auxiliary_verb
{
    my $self = shift;
    my $node = shift;
    if($node->tag() eq 'AUX')
    {
        if($node->deprel() =~ m/^(root|acl|xcomp)(:|$)/ && $node->lemma() =~ m/^(ansehen|auftreten|betrachten|bezeichnen|bleiben|funktionieren|lassen|sehen)$/)
        {
            $node->iset()->clear('verbtype');
            $node->set_tag('VERB');
        }
        elsif($node->deprel() =~ m/^aux(:|$)/ && $node->lemma() =~ m/^(bekommen|bleiben|brauchen|lassen)$/)
        {
            # We assume that the "auxiliary" verb is attached to an infinitive
            # which in fact should depend on the "auxiliary" (as xcomp).
            # We further assume (although it is not guaranteed) that all other
            # aux dependents of that infinitive are real auxiliaries.
            # If there were other spuriious auxiliaries, it would matter
            # in which order we reattach them.
            my $infinitive = $node->parent();
            # The VerbForm=Inf feature is often missing in German PUD.
            if($infinitive->iset()->verbform() eq '' && $infinitive->is_verb() && $infinitive->form() =~ m/(^sein$|en$)/i)
            {
                $infinitive->iset()->set('verbform', 'inf');
            }
            # In some cases it is not infinitive but participle: "bekommt angeboten".
            if($infinitive->is_infinitive() || $infinitive->is_participle())
            {
                my $parent = $infinitive->parent();
                my $deprel = $infinitive->deprel();
                $node->set_parent($parent);
                $node->set_deprel($deprel);
                $infinitive->set_parent($node);
                $infinitive->set_deprel('xcomp');
                # Subject, adjuncts and other auxiliaries go up.
                # Non-subject arguments remain with the infinitive.
                my @children = $infinitive->children();
                foreach my $child (@children)
                {
                    if($child->deprel() =~ m/^(([nc]subj|advmod|discourse|vocative|aux|mark|cc|punct)(:|$)|obl$)/ ||
                       $child->deprel() =~ m/^obl:([a-z]+)$/ && $1 ne 'arg')
                    {
                        $child->set_parent($node);
                    }
                }
                # We also need to change the part-of-speech tag from AUX to VERB.
                $node->iset()->clear('verbtype');
                $node->set_tag('VERB');
            }
        }
        elsif($node->lemma() =~ m/^(abkürzen|amtieren|anerkennen|anfühlen|ansehen|aufbauen|auftreten|ausmachen|bedeuten|befinden|befördern|bekannt|benennen|berufen|beschimpfen|beschreiben|bestehen|bestimmen|betiteln|betragen|bezeichnen|bilden|bleiben|darstellen|degradieren|deuten|dienen|duften|einstufen|empfinden|entlarven|entwickeln|entziffern|erachten|erheben|erklären|ernennen|eröffnen|erscheinen|erwähnen|erweisen|erweitern|feiern|feststellen|finden|folgen|fungieren|gehen|gelten|gestalten|glauben|gründen|halten|handeln|heißen|identifizieren|interpretieren|kosten|küren|lauten|liegen|listen|machen|messen|nehmen|nennen|nominieren|prägen|scheinen|schlagen|schmecken|schreiben|sehen|stehen|stellen|überzeugen|umbauen|umbenennen|umbilden|umwandeln|verarbeiten|vereidigen|verhaften|verlegen|versterben|vestehen|vorstellen|wählen|wandeln|wirken|wissen)$/ &&
              $node->deprel() =~ m/^cop(:|$)/)
        {
            my $pnom = $node->parent();
            my $parent = $pnom->parent();
            my $deprel = $pnom->deprel();
            # The nominal predicate may have been attached as a non-clause;
            # however, now we have definitely a clause.
            $deprel =~ s/^nsubj/csubj/;
            $deprel =~ s/^i?obj/ccomp/;
            $deprel =~ s/^(advmod|obl)/advcl/;
            $deprel =~ s/^(nmod|amod|appos)/acl/;
            $node->set_parent($parent);
            $node->set_deprel($deprel);
            $pnom->set_parent($node);
            $pnom->set_deprel('xcomp');
            # Subject, adjuncts and other auxiliaries go up.
            # We also have to raise conjunctions and punctuation, otherwise we risk nonprojectivities.
            # Noun modifiers remain with the nominal predicate.
            my @children = $pnom->children();
            foreach my $child (@children)
            {
                if($child->deprel() =~ m/^(([nc]subj|obj|advmod|discourse|vocative|aux|mark|cc|punct)(:|$)|obl$)/ ||
                   $child->deprel() =~ m/^obl:([a-z]+)$/ && $1 ne 'arg')
                {
                    $child->set_parent($node);
                }
            }
            # We also need to change the part-of-speech tag from AUX to VERB.
            $node->iset()->clear('verbtype');
            $node->set_tag('VERB');
        }
        elsif($node->lemma() eq 'werden' && $node->deprel() =~ m/^cop(:|$)/)
        {
            # "Werden" ("to become") is not a copula in UD but it can be an auxiliary (of passive voice and of future tense).
            # With nominal predicates however, it should be treated as the main verb.
            if($node->parent()->is_participle())
            {
                $node->set_deprel('aux:pass');
                my @siblings = $node->get_siblings();
                foreach my $sibling (@siblings)
                {
                    my $odeprel = $sibling->deprel();
                    my $ndeprel = $odeprel;
                    $ndeprel =~ s/^([nc]subj)$/$1:pass/;
                    $sibling->set_deprel($ndeprel) if($ndeprel ne $odeprel);
                }
            }
            elsif($node->parent()->is_infinitive())
            {
                # Periphrastic future tense.
                $node->set_deprel('aux');
            }
            else # probably a pseudo-copula with a secondary nominal predicate
            {
                my $pnom = $node->parent();
                my $parent = $pnom->parent();
                my $deprel = $pnom->deprel();
                # The nominal predicate may have been attached as a non-clause;
                # however, now we have definitely a clause.
                $deprel =~ s/^nsubj/csubj/;
                $deprel =~ s/^i?obj/ccomp/;
                $deprel =~ s/^(advmod|obl)/advcl/;
                $deprel =~ s/^(nmod|amod|appos)/acl/;
                $node->set_parent($parent);
                $node->set_deprel($deprel);
                $pnom->set_parent($node);
                $pnom->set_deprel('xcomp');
                # Subject, adjuncts and other auxiliaries go up.
                # We also have to raise conjunctions and punctuation, otherwise we risk nonprojectivities.
                # Noun modifiers remain with the nominal predicate.
                my @children = $pnom->children();
                foreach my $child (@children)
                {
                    if($child->deprel() =~ m/^(([nc]subj|obj|advmod|discourse|vocative|aux|mark|cc|punct)(:|$)|obl$)/ ||
                       $child->deprel() =~ m/^obl:([a-z]+)$/ && $1 ne 'arg')
                    {
                        $child->set_parent($node);
                    }
                }
                # We also need to change the part-of-speech tag from AUX to VERB.
                $node->iset()->clear('verbtype');
                $node->set_tag('VERB');
            }
        }
        # Some verbs were tagged AUX and appeared in coordination with other pseudo-auxiliaries.
        # Their deprel is 'conj'. Therefore the above branches did not catch them.
        ###!!! Note that this rule is not 100% precise. Sometimes the copula heads
        ###!!! its clause (because of ellipsis or because the predicate is a nested clause),
        ###!!! so it is not attached as 'cop' but it should be tagged 'AUX'. If it happens
        ###!!! to be attached as 'conj', then this rule will make it mistakenly 'VERB'
        ###!!! (see sentence train-s1080).
        elsif($node->deprel() =~ m/^conj(:|$)/ && $node->parent()->deprel() !~ m/^(aux|cop)(:|$)/)
        {
            $node->iset()->clear('verbtype');
            $node->set_tag('VERB');
        }
    }
}



#------------------------------------------------------------------------------
# Right-to-left appositions occur when a short nonverbal phrase introduces the
# sentence: "Danke, die Blumen sind eingetroffen."
#------------------------------------------------------------------------------
sub fix_right_to_left_apposition
{
    my $self = shift;
    my $node = shift;
    if($node->deprel() eq 'appos' && $node->parent()->ord() > $node->ord() && $node->parent()->deprel() eq 'root')
    {
        my $current_root = $node->parent();
        $node->set_parent($current_root->parent());
        $node->set_deprel('root');
        $current_root->set_parent($node);
        $current_root->set_deprel('appos');
    }
}



#------------------------------------------------------------------------------
# Genitive nouns are sometimes attached as 'det' instead of 'nmod'. Fix it.
#------------------------------------------------------------------------------
sub fix_genitive_noun_modifiers
{
    my $self = shift;
    my $node = shift;
    if($node->is_noun() && !$node->is_pronominal() && $node->is_genitive() && $node->deprel() eq 'det')
    {
        $node->set_deprel('nmod');
    }
}



#------------------------------------------------------------------------------
# Identifies German inherently reflexive verbs (echte reflexive Verben). Note
# that there are very few verbs where we can automatically say that the they
# are reflexive. In some cases they are mostly reflexive, but the transitive
# usage cannot be excluded, although it is rare, obsolete or limited to some
# dialects. In other cases the reflexive use has a meaning significantly
# different from the transitive use, and it would deserve to be annotated using
# expl:pv, but we cannot tell the two usages apart automatically.
#------------------------------------------------------------------------------
sub is_inherently_reflexive_verb
{
    my $self = shift;
    my $lemma = shift;
    # The following examples are taken from Knaurs Grammatik der deutschen Sprache, 1989
    # (first line) + some additions (second line).
    # with accusative
    my @irva = qw(
        bedanken beeilen befinden begeben erholen nähern schämen sorgen verlieben
        anfreunden weigern
    );
    # with dative
    my @irvd = qw(
        aneignen anmaßen ausbitten einbilden getrauen gleichbleiben vornehmen
    );
    my $re = join('|', (@irva, @irvd));
    return $lemma =~ m/^($re)$/;
}



#------------------------------------------------------------------------------
# Fixes known issues in features. This method is called after the relations
# have been fixed. However, UPOS tags, unlike features, should be fixed before
# the relations (see explanation in process_atree()).
#------------------------------------------------------------------------------
sub fix_morphology
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants({ordered => 1});
    foreach my $node (@nodes)
    {
        $self->fix_mwt_capitalization($node);
        my $form = $node->form();
        my $lemma = $node->lemma();
        my $iset = $node->iset();
        my $deprel = $node->deprel();
        if($lemma eq 'nicht')
        {
            $iset->set('polarity', 'neg');
        }
        # "ihres" is determiner, not adjective.
        if($node->tag() eq 'ADJ' && $node->conll_pos() =~ m/^P.+AT$/ && $lemma !~ m/^(nett|fein|genügend|direkt)$/i)
        {
            $node->iset()->set('prontype', 'prn');
        }
        # "Ein" can be a cardinal numeral ("one") or the indefinite article ("a").
        # If we want to analyze it as a numeral, we must make sure that the
        # Interset features do not contain prontype; otherwise the output tag
        # will be DET.
        if($form =~ m/^ein(e[rsmn]?)?$/i && $deprel eq 'nummod')
        {
            $lemma = 'ein';
            $node->set_lemma($lemma);
            $iset->clear('prontype');
            $iset->set('numtype', 'card');
            $node->set_tag('NUM');
        }
        # Getting lemmas of auxiliary verbs right is important because the
        # validator uses them to check that normal verbs are not tagged as
        # auxiliary.
        if($node->is_verb() || $node->tag() eq 'AUX')
        {
            if($form =~ m/^ha(ben|be?s?t?|s?t)$/i)
            {
                $lemma = 'haben';
                $node->set_lemma($lemma);
            }
            elsif($form =~ m/^(seyn|waren)$/i)
            {
                $lemma = 'sein';
                $node->set_lemma($lemma);
            }
            # There is even one occurrence of "wir" meaning "wird".
            elsif($form =~ m/^((ge)?w[eio]rd|wir$)/i)
            {
                $lemma = 'werden';
                $node->set_lemma($lemma);
            }
            elsif($form =~ m/^kanns$/i)
            {
                $lemma = 'können';
                $node->set_lemma($lemma);
            }
            elsif($form =~ m/^angefühlt$/i)
            {
                $lemma = 'anfühlen';
                $node->set_lemma($lemma);
            }
        }
        if($form =~ 'genannten' && $node->tag() eq 'AUX')
        {
            $node->iset()->set('pos', 'adj');
            $node->iset()->clear('verbtype');
            $node->iset()->set('verbform', 'part');
            $node->set_tag('ADJ');
        }
        # 'ein' can work as the indefinite article or as the number 'one' and the borderline is fuzzy.
        # In case of conflict, trust the dependency relation.
        if($lemma eq 'ein' && $node->deprel() =~ m/^nummod(:|$)/)
        {
            $node->iset()->set('pos', 'num');
            $node->iset()->set('numtype', 'card');
            $node->iset()->clear('prontype');
            $node->iset()->clear('definite');
        }
        # Occasionally an auxiliary verb is tagged VERB instead of AUX.
        # In case of conflict, trust the dependency relation.
        if($iset->is_verb() && !$iset->is_auxiliary() && $deprel =~ m/^aux(:|$)/)
        {
            $iset->set('verbtype', 'aux');
            $node->set_tag('AUX');
        }
        # The conjunction "dass" is often misspelled "das" and then wrongly analyzed as pronoun or determiner.
        # Some of the errors can be recognized by the correct dependency relation 'mark'.
        if($form =~ m/^das$/i && $iset->is_pronominal() && $deprel eq 'mark')
        {
            $lemma = 'dass';
            $node->set_lemma($lemma);
            $iset->set_hash({'pos' => 'conj', 'conjtype' => 'sub', 'typo' => 'yes'});
            $node->set_tag('SCONJ');
            $node->set_conll_pos('KOUS');
            $node->set_misc_attr('CorrectForm', 'dass'); ###!!! We should mimic the capitalization of the wrong form here.
        }
        # The pronominal adverbs "worin", "wonach", "wovon" etc are often tagged PRON and attached as 'mark'.
        if($form =~ m/^wo\pL/i && $iset->is_pronominal() && $deprel eq 'mark')
        {
            $iset->set('pos', 'adv');
            $node->set_tag('ADV');
            $deprel = 'advmod';
            $node->set_deprel($deprel);
        }
        # Unknown adverbs, often abbreviated such as "usw."
        if($node->tag() eq 'X' && $deprel eq 'advmod')
        {
            $iset->set('pos', 'adv');
            $node->set_tag('ADV');
        }
        # The foreign prepositions "of", "from", "de" etc. in foreign named entities are tagged PROPN but attached as 'case'.
        $self->restructure_propn_span_of_foreign_preposition($node);
        $deprel = $node->deprel();
        # The preposition "von" is wrongly tagged PROPN when it occurs in a personal name such as "Fritz von Opel".
        if($form =~ m/^(von|als|an|für|gegen|in|mit|nach|ohne|über|unter|zu)$/i && $iset->is_proper_noun() && $deprel eq 'case')
        {
            $iset->set_hash({'pos' => 'adp'});
            $node->set_tag('ADP');
        }
        # The English possessive "'s" in named entities is tagged PRON but attached as 'case'.
        if($form =~ m/^'s$/i && $iset->is_pronominal() && $node->parent()->ord() < $node->ord() && $deprel eq 'case') #'
        {
            $iset->set_hash({'foreign' => 'yes'});
            $node->set_tag('X');
            $lemma = "'s";
            $node->set_lemma($lemma);
            $deprel = 'flat';
            $node->set_deprel($deprel);
        }
        # Infinitival "zu" was not converted from 'aux' to 'mark' when the parent was an adjectival participle.
        if($form =~ m/^zu$/i && $iset->is_particle() && $deprel eq 'aux')
        {
            $deprel = 'mark';
            $node->set_deprel($deprel);
        }
        # The "&" symbol is escaped as "&amp;" and often tagged NOUN or PROPN.
        $form = '&' if($form eq '&amp;');
        if($form eq '&')
        {
            $node->set_form($form);
            $lemma = '&';
            $node->set_lemma($lemma);
            $iset->set_hash({'pos' => 'sym'});
            $node->set_tag('SYM');
        }
    }
    # It is possible that we changed the form of a multi-word token.
    # Therefore we must re-generate the sentence text.
    $root->get_zone()->set_sentence($root->collect_sentence_text());
}



#------------------------------------------------------------------------------
# A foreign preposition tagged PROPN is usually part of a foreign multi-word
# named entity. We want to analyze the named entity as a flat structure.
#------------------------------------------------------------------------------
sub restructure_propn_span_of_foreign_preposition
{
    my $self = shift;
    my $node = shift;
    # In the original GSD data, foreign prepositions are treated as 'case'
    # dependents, despite being tagged PROPN.
    if($node->is_proper_noun() && $node->deprel() eq 'case' &&
       $node->form() =~ m/^(about|against|as|at|by|for|from|inside|into|of|off|on|to|upon|with|de|d'|du|à|au|aux|en|par|sous|sur|a|al|del|hasta|da|do|dos|di|della|delle|cum|pro|van|voor|på|na|nad|z)$/i #'
       # A similar problem can occur with foreign auxiliary verbs.
       ||
       $node->is_proper_noun() && $node->deprel() =~ m/^aux(:|$)/ &&
       $node->form() =~ m/^(can|do|'m|to|will)$/i #'
      )
    {
        # Find the span of proper nouns this node is part of.
        my $root = $node->get_root();
        my @nodes = $root->get_descendants({'ordered' => 1});
        my $prev_is_propn = 0;
        my $span_begin;
        my $span_end;
        my $span_found = 0;
        for(my $i = 0; $i <= $#nodes; $i++)
        {
            my $this_is_propn = $nodes[$i]->is_proper_noun();
            # Occasionally a PROPN span is interleaved with hyphens: "Stratford-upon-Avon"
            $this_is_propn = 1 if(!$this_is_propn && $prev_is_propn && $nodes[$i]->form() eq '-');
            if($this_is_propn && !$prev_is_propn)
            {
                $span_begin = $i;
            }
            elsif(!$this_is_propn && $prev_is_propn)
            {
                if($span_found)
                {
                    $span_end = $i-1;
                    last;
                }
                else
                {
                    $span_begin = undef;
                    $span_end = undef;
                }
            }
            if($this_is_propn && $nodes[$i] == $node)
            {
                $span_found = 1;
            }
            $prev_is_propn = $this_is_propn;
        }
        if($span_found)
        {
            if(!defined($span_end))
            {
                $span_end = $#nodes;
            }
            # Identify edges incoming to the span. Hopefully there is only one.
            my @incoming;
            for(my $i = $span_begin; $i <= $span_end; $i++)
            {
                my $parent = $nodes[$i]->parent();
                if($parent->ord() < $nodes[$span_begin]->ord() || $parent->ord() > $nodes[$span_end]->ord())
                {
                    push(@incoming, {'parent' => $parent, 'deprel' => $nodes[$i]->deprel()});
                }
            }
            ###!!! If there are multiple incoming edges, we should identify the subtree of which our node is member.
            ###!!! But it is even not guaranteed that the subtree corresponds to a contiguous subspan.
            ###!!! For now, let's take the first incoming edge and ignore the others.
            if(scalar(@incoming) >= 1)
            {
                # To prevent cycles, we must first attach all span nodes to the root, then to their correct parents.
                for(my $i = $span_begin; $i <= $span_end; $i++)
                {
                    $nodes[$i]->set_parent($root);
                    # Get rid of German morphology, if any.
                    unless($nodes[$i]->form() eq '-')
                    {
                        $nodes[$i]->iset()->set_hash({'pos' => 'noun', 'nountype' => 'prop', 'foreign' => 'yes'});
                    }
                }
                $nodes[$span_begin]->set_parent($incoming[0]{parent});
                $nodes[$span_begin]->set_deprel($incoming[0]{deprel});
                for(my $i = $span_begin+1; $i <= $span_end; $i++)
                {
                    $nodes[$i]->set_parent($nodes[$span_begin]);
                    unless($nodes[$i]->form() eq '-')
                    {
                        $nodes[$i]->set_deprel('flat');
                    }
                }
            }
            else
            {
                log_warn("Something must be wrong. We did not find any edge incoming to the PROPN span of node '".$node->form()."'");
            }
        }
        else
        {
            log_warn("Something must be wrong. We did not find the PROPN span of node '".$node->form()."'");
        }
    }
}



#------------------------------------------------------------------------------
# Identifies and returns the subject of a verb or another predicate. If the
# verb is copula or auxiliary, finds the subject of its parent.
#------------------------------------------------------------------------------
sub get_subject
{
    my $self = shift;
    my $node = shift;
    my @subj = grep {$_->deprel() =~ m/subj/} $node->children();
    # There should not be more than one subject (coordination is annotated differently).
    # The caller expects at most one node, so we will not return more than that, even if present.
    return $subj[0] if(scalar(@subj)>0);
    return undef if($node->is_root());
    return $self->get_subject($node->parent()) if($node->deprel() =~ m/^(aux|cop)/);
    return undef;
}



#------------------------------------------------------------------------------
# After changes done to Interset (including part of speech) generates the
# universal part-of-speech tag anew.
#------------------------------------------------------------------------------
sub regenerate_upos
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants();
    foreach my $node (@nodes)
    {
        $node->set_tag($node->iset()->get_upos());
    }
}



#------------------------------------------------------------------------------
# Makes capitalization of muti-word tokens consistent with capitalization of
# their parts.
#------------------------------------------------------------------------------
sub fix_mwt_capitalization
{
    my $self = shift;
    my $node = shift;
    # Is this node part of a multi-word token?
    if($node->is_fused())
    {
        my $pform = $node->form();
        my $fform = $node->get_fusion();
        # It is not always clear whether we want to fix the mwt or the part.
        # In German however, the most frequent error seems to be that in the
        # beginning of a sentence, the mwt is not capitalized while its first
        # part is.
        if($node->get_fusion_start() == $node && $node->ord() == 1 && is_capitalized($pform) && is_lowercase($fform))
        {
            $fform =~ s/^(.)/\u$1/;
            $node->set_fused_form($fform);
        }
        # Occasionally the problem occurs also in the middle of the sentence, e.g. after punctuation that might terminate a sentence but does not here.
        # In such cases we want to lowercase the first part.
        elsif($node->get_fusion_start() == $node && is_capitalized($pform) && is_lowercase($fform))
        {
            $node->set_form(lc($pform));
        }
    }
}



#------------------------------------------------------------------------------
# Checks whether a string is all-uppercase.
#------------------------------------------------------------------------------
sub is_uppercase
{
    my $string = shift;
    return $string eq uc($string);
}



#------------------------------------------------------------------------------
# Checks whether a string is all-lowercase.
#------------------------------------------------------------------------------
sub is_lowercase
{
    my $string = shift;
    return $string eq lc($string);
}



#------------------------------------------------------------------------------
# Checks whether a string is capitalized.
#------------------------------------------------------------------------------
sub is_capitalized
{
    my $string = shift;
    return 0 if(length($string)==0);
    $string =~ m/^(.)(.*)$/;
    my $head = $1;
    my $tail = $2;
    return is_uppercase($head) && !is_uppercase($tail);
}



#------------------------------------------------------------------------------
# Collects all nodes in a subtree of a given node. Useful for fixing known
# annotation errors, see also get_node_spanstring(). Returns ordered list.
#------------------------------------------------------------------------------
sub get_node_subtree
{
    my $self = shift;
    my $node = shift;
    my @nodes = $node->get_descendants({'add_self' => 1, 'ordered' => 1});
    return @nodes;
}



#------------------------------------------------------------------------------
# Collects word forms of all nodes in a subtree of a given node. Useful to
# uniquely identify sentences or their parts that are known to contain
# annotation errors. (We do not want to use node IDs because they are not fixed
# enough in all treebanks.) Example usage:
# if($self->get_node_spanstring($node) =~ m/^peça a URV em a sua mesada$/)
#------------------------------------------------------------------------------
sub get_node_spanstring
{
    my $self = shift;
    my $node = shift;
    my @nodes = $self->get_node_subtree($node);
    return join(' ', map {$_->form() // ''} (@nodes));
}



1;

=over

=item Treex::Block::HamleDT::DE::FixUD

This is a temporary block that should fix selected known problems in the German UD treebank.

=back

=head1 AUTHORS

Daniel Zeman <zeman@ufal.mff.cuni.cz>

=head1 COPYRIGHT AND LICENSE

Copyright © 2016, 2017 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
