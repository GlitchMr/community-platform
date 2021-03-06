package DDGC::DB::Result::Token::Language;

use DBIx::Class::Candy -components => [ 'TimeStamp', 'InflateColumn::DateTime', 'InflateColumn::Serializer', 'EncodedColumn' ];

table 'token_language';

column id => {
	data_type => 'bigint',
	is_auto_increment => 1,
};
primary_key 'id';

column token_id => {
	data_type => 'bigint',
	is_nullable => 0,
};

column token_domain_language_id => { 
	data_type => 'bigint',
	is_nullable => 0,
};

column notes => {
	data_type => 'text',
	is_nullable => 1,
};

column msgstr0 => {
	data_type => 'text',
	is_nullable => 1,
};
sub msgstr { shift->msgstr0(@_) }

column msgstr1 => {
	data_type => 'text',
	is_nullable => 1,
};

column msgstr2 => {
	data_type => 'text',
	is_nullable => 1,
};

column msgstr3 => {
	data_type => 'text',
	is_nullable => 1,
};

column msgstr4 => {
	data_type => 'text',
	is_nullable => 1,
};

column msgstr5 => {
	data_type => 'text',
	is_nullable => 1,
};

column translator_users_id => {
	data_type => 'bigint',
	is_nullable => 1,
};

sub msgstr_index_max { 5 }

column data => {
	data_type => 'text',
	is_nullable => 1,
	serializer_class => 'YAML',
};

column created => {
	data_type => 'timestamp with time zone',
	set_on_create => 1,
};

column updated => {
	data_type => 'timestamp with time zone',
	set_on_create => 1,
	set_on_update => 1,
};

belongs_to 'token', 'DDGC::DB::Result::Token', 'token_id';
belongs_to 'token_domain_language', 'DDGC::DB::Result::Token::Domain::Language', 'token_domain_language_id';

belongs_to 'translator_user', 'DDGC::DB::Result::User', 'translator_users_id', { join_type => 'left' };

has_many 'token_language_translations', 'DDGC::DB::Result::Token::Language::Translation', 'token_language_id';

unique_constraint [qw/ token_id token_domain_language_id /];

sub gettext_snippet {
	my ( $self, $fallback ) = @_;
	my %vars;
	my $msgstr_index_max = $self->token_domain_language->language->nplurals - 1;
	if ($self->token->msgid_plural) {
		for (0..$msgstr_index_max) {
			my $func = 'msgstr'.$_;
			my $result = $self->$func;
			$vars{'msgstr['.$_.']'} = $self->gettext_escape($result) if $result;
		}
	} else {
		$vars{'msgstr'} = $self->gettext_escape($self->msgstr0) if $self->msgstr0;
	}
	return unless %vars || $fallback;
	$vars{msgid} = $self->gettext_escape($self->token->msgid);
	$vars{msgctxt} = $self->gettext_escape($self->token->msgctxt) if $self->token->msgctxt;
	if ($self->token->msgid_plural) {
		$vars{msgid_plural} = $self->gettext_escape($self->token->msgid_plural);
		for (0..$msgstr_index_max) {
			$vars{'msgstr['.$_.']'} = $self->gettext_escape($self->token->msgid_plural)
				unless defined $vars{'msgstr['.$_.']'};
		}
	} else {
		$vars{msgstr} = $self->gettext_escape($self->token->msgid)
			unless defined $vars{msgstr};
	}
	return "\n".$self->gettext_snippet_formatter(%vars);
}

sub gettext_escape {
	my ( $self, $content ) = @_;
	$content =~ s/\n/\\n/g;
	$content =~ s/"/\\"/g;
	return $content;
}

sub gettext_snippet_formatter {
	my ( $self, %vars ) = @_;
	my $return;
	for (qw( msgctxt msgid msgid_plural )) {
		$return .= $_.' "'.(delete $vars{$_}).'"'."\n" if $vars{$_};
	}
	for (sort { $a cmp $b } keys %vars) {
		$return .= $_.' "'.(delete $vars{$_}).'"'."\n";
	}
	return $return;
}

sub set_user_translation {
	my ( $self, $user, $translation ) = @_;
	if ($user->can_speak($self->token_domain_language->language->locale)) {
		$self->update_or_create_related('token_language_translations',{
			%{$translation},
			user => $user->db,
		},{
			key => 'token_language_translation_token_language_id_username',
		});
	} else {
		die "you dont speak the language you are going to translate!";
	}
}

sub set_translation {
	my ( $self, $translation ) = @_;
	for (0..$self->msgstr_index_max) {
		my $func = 'msgstr'.$_;
		$self->$func($translation->$func);
	}
	$self->translator_users_id($translation->user->id) if $translation->user;
}

sub auto_use {
	my ( $self ) = @_;
	my @translations = $self->search_related('token_language_translations',{},{
		order_by => [ 'me.updated', 'me.id' ],
		prefetch => { user => 'user_languages' },
	})->all;
	my %first;
	my %grade;
	my %votes;
	for (@translations) {
		my $translation = $_;
		if (defined ($first{$translation->key})) {
			my $old = $first{$translation->key};
			my $translator = $translation->user;
			$old->set_user_vote($translator,1);
			for my $vote ($translation->votes) {
				$old->set_user_vote($vote->user,1);
			}
			$translation->delete;
			$translation = $old;
		} else {
			$first{$translation->key} = $translation;
		}
		my $translator_translation_language = $translation->user->search_related('user_languages',{
			language_id => $self->token_domain_language->language->id,
		})->first;
		$grade{$translation->key} = defined $translator_translation_language ? $translator_translation_language->grade : 0;
		for my $vote ($translation->votes) {
			my $translation_language = $vote->user->search_related('user_languages',{
				language_id => $self->token_domain_language->language->id,
			})->first;
			my $translation_grade = $translation_language ? $translation_language->grade : 0;
			my $best_grade = defined $grade{$translation->key} ? $grade{$translation->key} : 0;
			$grade{$translation->key} = $translation_grade if $translation_grade > $best_grade;
		}
		$votes{$translation->key} = $translation->vote_count;
	}
	my $best;
	for (keys %first) {
		if ($best) {
			$best = $first{$_} if $votes{$_} > $votes{$best->key};
			$best = $first{$_} if $votes{$_} == $votes{$best->key}
								&& $grade{$_} > $grade{$best->key};
		} else {
			$best = $first{$_};
		}
	}
	if ($best) {
		$self->set_translation($best);
		return $self->update;
	}
}

sub max_msgstr_index {
	my ( $self ) = @_;
	if ( $self->token->msgid_plural ) {
		return $self->token_domain_language->language->nplurals_index;
	} else {
		return 0;
	}
}

sub translations {
    my ( $self, $user, $for_other ) = @_;
    return $self->token_language_translations unless $user;
    my $is_user = sub { $_->username eq $user->username };
    my @tokens = $self->token_language_translations;

    return grep { $is_user->($_) } @tokens unless ($for_other);
    return grep { !$is_user->($_) } @tokens;
}

# the same code, just different written (for people who have no clue of CODEREF)
# sub translations {
	# my ( $self, $user, $for_other ) = @_;
	# return $self->token_language_translations unless $user;
	# my @results;
	# for (@{$self->token_language_translations}) {
		# my $is_user = $_->username eq $user->username;
		# return $_ if $is_user and not $for_other;
		# push @results, $_ unless $is_user;
	# }
	# return @results;
# }

use overload '""' => sub {
	my $self = shift;
	return 'Token-Language #'.$self->id;
}, fallback => 1;

1;
