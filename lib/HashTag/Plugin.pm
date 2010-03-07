package HashTag::Plugin;

use strict;

# CHANGELOG For Version 2.5
# v3 BETA: Removed default intro if blank.
# v3 BETA: Removed XML::Atom dependecy
# v4 BETA: Changed selection Radio buttons to single select list.
# v5 BETA: Support for scheduled posts
# v6 BETA: Refactored tags to hashtags into function
#          Refactored build tweet into function
# v7 BETA: Check for proxy configuration         

sub instance {
    return mt->component("HashTag");
}

sub xfrm_edit {
    my ( $cb, $app, $tmpl ) = @_;
    my $cfg        = instance()->get_config_hash( 'blog:' . $app->blog->id );
    my $selected_0 = q{};
    my $selected_1 = q{};
    my $selected_2 = q{};
    my $selected_3 = q{};
    if ( $cfg->{tw_share} eq '0' ) { $selected_0 = 'selected="selected"'; }
    if ( $cfg->{tw_share} eq '1' ) { $selected_1 = 'selected="selected"'; }
    if ( $cfg->{tw_share} eq '2' ) { $selected_2 = 'selected="selected"'; }
    if ( $cfg->{tw_share} eq '3' ) { $selected_3 = 'selected="selected"'; }

    my $setting = <<END_TMPL;
			<mtapp:setting
			id="tw_share"
			label="HashTag">
            <select name="tw_share" id="tw_share" class="full-width">
            <option value="0" $selected_0 >Don't Tweet</value>
            <option value="1" $selected_1 >Tweet without HashTags</option>
            <option value="2" $selected_2 >Tweet with #$cfg->{tw_community}</option>
            <option value="3" $selected_3 >Tweet tags as HashTags</option>
            </select>
			</mtapp:setting>
END_TMPL

    $$tmpl =~ s{(<mtapp:setting
            id="status"
            label="<__trans phrase="Status">"
            help_page="entries"
            help_section="status">)}{$setting$1}msg;
}

sub hdlr_post_save {
    my ( $cb, $app, $obj, $orig ) = @_;
    my $cfg = instance()->get_config_hash( 'blog:' . $app->blog->id );

    return $obj unless $app->param('tw_share');
    return $obj unless ( $cfg->{tw_username} && $cfg->{tw_password} );
    return $obj if $obj->status != MT::Entry::RELEASE();

    _build_tweet( $cfg, $obj, $app );
}

sub hdlr_scheduled_post {
    my ( $cb, $app, $obj ) = @_;
    my $cfg = instance()->get_config_hash( 'blog:' . $obj->blog_id );

    return $obj unless $cfg->{tw_share};
    return $obj unless ( $cfg->{tw_username} && $cfg->{tw_password} );
    return $obj if $obj->status != MT::Entry::RELEASE();

    _build_tweet( $cfg, $obj, $app );
}

sub _tag_to_hashtag {

    # convert entry tags into hash tags and populate $hashtags
    # thanks to Jay Allen http://endevver.com/

    my ( $obj ) = @_;
    require MT::Tag;
    my @normalized;
    foreach my $tagname ( $obj->tags ) {
        next unless index( $tagname, '@' );
        my $tag = MT::Tag->new;
        $tag->name($tagname);
        push( @normalized, $tag->normalize );
    }
    my $hashtag = ' #' . join( ' #', @normalized );
    return $hashtag;
}

sub _build_tweet {
    my ( $cfg, $obj, $app ) = @_;
    my $tweet = q{};
    my $intro = q{};
    my $title = q{};
    my $share = q{};

    if ( $cfg->{tw_intro} ) { $intro = $cfg->{tw_intro}; }

    my $enc = MT->instance->config('PublishCharset') || undef;
    $title = MT::I18N::encode_text( $obj->title, $enc, 'utf-8' );
    
    # need to work out if _build_tweet has been called from a save action
    # or from a schedule post by checking if $app has the tw_share param
    # if not then it has been called from a schedule post so we need to use
    # the default configuration.

    if ( defined { $app->param('tw_share') } ) {
        $share = $app->param('tw_share');

    }
    else {
        $share = $cfg->{tw_share};
    }

    if ( $share eq '1' ) {
        $tweet = $intro . ' ' 
        . $title . ' ' 
        . $obj->permalink;
    }
    if ( $share eq '2' ) {
        $tweet =
            $intro . ' ' 
          . $title . ' '
          . $obj->permalink . ' #'
          . $cfg->{tw_community};
    }
    if ( $share eq '3' ) {
        $tweet =
          $intro . ' ' 
        . $title . ' ' 
        . $obj->permalink 
        . _tag_to_hashtag($obj);
    }

    _update_twitter( $cfg, $tweet );

    return;
}

sub _update_twitter {
    my ( $cfg, $tweet ) = @_;
    MT->log( { message => 'Tweeting' . ' ' . $tweet, } );
    require LWP::UserAgent;
    my $ua = LWP::UserAgent->new;

    # Check for Proxy Server
    # thanks to Alvar Freude http://www.perl-blog.de

    if (my $proxy = MT::ConfigMgr->instance->HTTPProxy) {
        $ua->proxy('http', $proxy);
    }
    $ua->credentials( 'twitter.com:80', 'Twitter API',
    $cfg->{tw_username} => $cfg->{tw_password}, );
    my $post_url = 'http://twitter.com/statuses/update.xml';
    my $response = $ua->post( $post_url, [ status => $tweet ] )
      or return MT->log( { message => 'Update to Twitter failed. Sorry.', } );
    return;
}

1;

