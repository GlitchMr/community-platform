package DDGC::DB::ResultSet::Token::Domain;

use Moose;
extends 'DBIx::Class::ResultSet';
 
sub sorted {
	my ( $self ) = @_;
	$self->search({}, {
		order_by => { -desc => 'me.sorting' },
	});
}
 
1;