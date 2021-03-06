package DDGC::Web::Controller::Comment;
use Moose;
use namespace::autoclean;

BEGIN {extends 'Catalyst::Controller'; }

sub base :Chained('/base') :PathPart('comment') :CaptureArgs(0) {
    my ( $self, $c ) = @_;
}

sub do :Chained('base') :CaptureArgs(0) {
    my ( $self, $c ) = @_;
}

sub latest :Chained('do') :Args(0) {
    my ( $self, $c ) = @_;
	$c->pager_init($c->action,20);
	$c->stash->{latest_comments} = [($c->d->rs('Comment')->search({},{
		order_by => 'me.created',
		page => $c->stash->{page},
		rows => $c->stash->{pagesize},
	}))];
	$c->add_bc('Latest comments', $c->chained_uri('Comment','latest'));
}

sub delete : Chained('do') Args(1) {
    my ( $self, $c, $id ) = @_;
    my $comment = $c->d->rs('Comment')->single({ id => $id });
    return unless $comment;
    return unless $c->user && ($c->user->admin || $c->user->id == $comment->user->id);
    $comment->content('This comment has been deleted.');
    $comment->users_id(0);
    $comment->update;
    
    my $redirect = $c->req->headers->referrer || '/';
    $c->response->redirect($redirect);
}

sub add :Chained('base') :Args(2) {
    my ( $self, $c, $context, $context_id ) = @_;
    return unless $c->user || ! $c->stash->{no_reply};
	if ($c->req->params->{content}) {
		$c->d->add_comment($context, $context_id, $c->user, $c->req->params->{content});
	}
	if ($c->req->params->{from}) {
		$c->response->redirect($c->req->params->{from});
		return $c->detach;
	}
}

__PACKAGE__->meta->make_immutable;

1;
