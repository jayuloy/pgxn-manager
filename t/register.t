#!/usr/bin/env perl

use 5.12.0;
use utf8;
use Test::More tests => 410;
#use Test::More 'no_plan';
use lib '/Users/david/dev/github/Plack/lib';
use Plack::Test;
use HTTP::Request::Common;
use PGXN::Manager;
use PGXN::Manager::Router;
use HTTP::Message::PSGI;
use Test::XML;
use Test::XPath;
use lib 't/lib';
use TxnTest;
use XPathTest;

my $app      = PGXN::Manager::Router->app;
my $mt       = PGXN::Manager::Locale->accept('en');
my $desc     = $mt->maketext('Request a PGXN Account and start distributing your PostgreSQL extensions!');
my $keywords = 'pgxn,postgresql,distribution,register,account,user,nickname';
my $h1       = $mt->maketext('Request an Account');
my $p        = $mt->maketext(q{Want to distribute your PostgreSQL extensions on PGXN? Register here to request an account. We'll get it approved post haste.});

# Request a registration form.
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET '/request'), 'Fetch /request';
    ok $res->is_success, 'Should get a successful response';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    XPathTest->test_basics($tx, $req, $mt, {
        desc        => $desc,
        keywords    => $keywords,
        h1          => $h1,
    });

    # Check the content
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 3, '... It should have three subelements');
        $tx->is('./h1', $h1, '... The title h1 should be set');
        $tx->is('./p', $p, '... Intro paragraph should be set');
    });

    # Now examine the form.
    $tx->ok('/html/body/div[@id="content"]/form[@id="reqform"]', sub {
        for my $attr (
            [action  => '/register'],
            [enctype => 'application/x-www-form-urlencoded'],
            [method  => 'post']
        ) {
            $tx->is(
                "./\@$attr->[0]",
                $attr->[1],
                qq{... Its $attr->[0] attribute should be "$attr->[1]"},
            );
        }
        $tx->is('count(./*)', 3, '... It should have three subelements');
        $tx->ok('./fieldset[1]', '... Test first fieldset', sub {
            $tx->is('./@id', 'reqessentials', '...... It should have the proper id');
            $tx->is('count(./*)', 9, '...... It should have nine subelements');
            $tx->is(
                './legend',
                $mt->maketext('The Essentials'),
                '...... Its legend should be correct'
            );
            my $i = 0;
            for my $spec (
                {
                    id    => 'name',
                    title => $mt->maketext('What does your mother call you?'),
                    label => $mt->maketext('Name'),
                    type  => 'text',
                    phold => 'Barack Obama',
                },
                {
                    id    => 'email',
                    title => $mt->maketext('Where can we get hold of you?'),
                    label => $mt->maketext('Email'),
                    type  => 'email',
                    phold => 'you@example.com',
                },
                {
                    id    => 'uri',
                    title => $mt->maketext('Got a blog or personal site?'),
                    label => $mt->maketext('URI'),
                    type  => 'url',
                    phold => 'http://blog.example.com/',
                },
                {
                    id    => 'nickname',
                    title => $mt->maketext('By what name would you like to be known? Letters, numbers, and dashes only, please.'),
                    label => $mt->maketext('Nickname'),
                    type  => 'text',
                    phold => 'bobama',
                },
            ) {
                ++$i;
                $tx->ok("./label[$i]", "...... Test $spec->{id} label", sub {
                    $_->is('./@for', $spec->{id}, '......... Check "for" attr' );
                    $_->is('./@title', $spec->{title}, '......... Check "title" attr' );
                    $_->is('./text()', $spec->{label}, '......... Check its value');
                });
                $tx->ok("./input[$i]", "...... Test $spec->{id} input", sub {
                    $_->is('./@id', $spec->{id}, '......... Check "id" attr' );
                    $_->is('./@name', $spec->{id}, '......... Check "name" attr' );
                    $_->is('./@type', $spec->{type}, '......... Check "type" attr' );
                    $_->is('./@title', $spec->{title}, '......... Check "title" attr' );
                    $_->is('./@placeholder', $spec->{phold}, '......... Check "placeholder" attr' );
                });
            }
        });
        $tx->ok('./fieldset[2]', '... Test second fieldset', sub {
            $tx->is('./@id', 'reqwhy', '...... It should have the proper id');
            $tx->is('count(./*)', 3, '...... It should have three subelements');
            $tx->is('./legend', $mt->maketext('Your Plans'), '...... It should have a legend');
            my $t = $mt->maketext('So what are your plans for PGXN? What do you wanna release?');
            $tx->ok('./label', '...... Test the label', sub {
                $_->is('./@for', 'why', '......... It should be for the right field');
                $_->is('./@title', $t, '......... It should have the title');
                $_->is('./text()', $mt->maketext('Why'), '......... It should have label');
            });
            $tx->ok('./textarea', '...... Test the textarea', sub {
                $_->is('./@id', 'why', '......... It should have its id');
                $_->is('./@name', 'why', '......... It should have its name');
                $_->is('./@title', $t, '......... It should have the title');
                $_->is('./@placeholder', $mt->maketext('I would like to release the following killer extensions on PGXN:

* foo
* bar
* baz', '......... It should have its placeholder'));
                $_->is('./text()', '', '......... And it should be empty')
            });
        });
        $tx->ok('./input[@type="submit"]', '... Test input', sub {
            for my $attr (
                [id => 'submit'],
                [name => 'submit'],
                [class => 'submit'],
                [value => $mt->maketext('Pretty Please!')],
            ) {
                $_->is(
                    "./\@$attr->[0]",
                    $attr->[1],
                    qq{...... Its $attr->[0] attribute should be "$attr->[1]"},
                );
            }
        });
    }, 'Test request form');
};

# Okay, let's submit the form.
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(POST '/register', [
        name     => 'Tom Lane',
        email    => 'tgl@pgxn.org',
        uri      => '',
        nickname => 'tgl',
        why      => 'In short, +1 from me. Regards, Tom Lane',
    ]), 'POST tgl to /register';
    ok $res->is_redirect, 'It should be a redirect response';
    is $res->headers->header('location'), '/thanks', 'Should redirect to /thanks';

    # And now Tom Lane should be registered.
    PGXN::Manager->conn->run(sub {
        is_deeply $_->selectrow_arrayref(q{
            SELECT full_name, email, uri, status
              FROM users
             WHERE nickname = ?
        }, undef, 'tgl'), ['Tom Lane', 'tgl@pgxn.org', undef, 'new'], 'TGL should exist';
    });
};

# Awesome. Let's get a nickname conflict and see how it handles it.
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(POST '/register', [
        name     => 'Tom Lane',
        email    => 'tgl@pgxn.org',
        uri      => 'http://tgl.example.org/',
        nickname => 'tgl',
        why      => 'In short, +1 from me. Regards, Tom Lane',
    ]), 'POST tgl to /register again';
    ok !$res->is_redirect, 'It should not be a redirect response';
    is $res->code, 409, 'Should have 409 status code';

    # So check the content.
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    XPathTest->test_basics($tx, $req, $mt, {
        desc        => $desc,
        keywords    => $keywords,
        h1          => $h1,
    });

    # Now verify that we have the error message and that the form fields are
    # filled-in.
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 4, '... It should have four subelements');
        $tx->is('./h1', $h1, '... The title h1 should be set');
        $tx->is('./p[1]', $p, '... Intro paragraph should be set');
        my $err = $mt->maketext('The Nickname “[_1]” is already taken. Sorry about that.', 'tgl');
        $tx->is('./p[@class="error"]', $err, '... Error paragraph should be set');

        # Check the form fields.
        $tx->ok('./form[@id="reqform"]/fieldset[1]', '... Check first fieldset', sub {
            $tx->is('./input[@id="name"]/@value', 'Tom Lane', '...... Name should be set');
            $tx->is('./input[@id="email"]/@value', 'tgl@pgxn.org', '...... Email should be set');
            $tx->is('./input[@id="uri"]/@value', 'http://tgl.example.org/', '...... URI should be set');
            $tx->is('./input[@id="nickname"]/@value', '', '...... Nickname should not be set');
        });

        $tx->ok('./form[@id="reqform"]/fieldset[2]', '... Check second fieldset', sub {
            $tx->is(
                './textarea[@id="why"]',
                'In short, +1 from me. Regards, Tom Lane',
                '...... Why textarea should be set'
            );
        });
    });
};

# Start a new test transaction and create Tom again.
TxnTest->restart;
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(POST '/register', [
        name     => 'Tom Lane',
        email    => 'tgl@pgxn.org',
        uri      => '',
        nickname => 'tgl',
        why      => 'In short, +1 from me. Regards, Tom Lane',
    ]), 'POST valid tgl to /register again';
    ok $res->is_redirect, 'It should be a redirect response';
    is $res->headers->header('location'), '/thanks', 'Should redirect to /thanks';

    # And now Tom Lane should be registered.
    PGXN::Manager->conn->run(sub {
        is_deeply $_->selectrow_arrayref(q{
            SELECT full_name, email, uri, status
              FROM users
             WHERE nickname = ?
        }, undef, 'tgl'), ['Tom Lane', 'tgl@pgxn.org', undef, 'new'], 'TGL should exist';
    });
};

# Now try a conflicting email address.
test_psgi $app => sub {
    local $ENV{FOO} = 1;
    my $cb = shift;
    ok my $res = $cb->(POST '/register', [
        name     => 'Tom Lane',
        email    => 'tgl@pgxn.org',
        uri      => 'http://tgl.example.org/',
        nickname => 'yodude',
        why      => 'In short, +1 from me. Regards, Tom Lane',
    ]), 'POST yodude to /register';
    ok !$res->is_redirect, 'It should not be a redirect response';
    is $res->code, 409, 'Should have 409 status code';

    # So check the content.
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    XPathTest->test_basics($tx, $req, $mt, {
        desc        => $desc,
        keywords    => $keywords,
        h1          => $h1,
    });

    # Now verify that we have the error message and that the form fields are
    # filled-in.
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 4, '... It should have four subelements');
        $tx->is('./h1', $h1, '... The title h1 should be set');
        $tx->is('./p[1]', $p, '... Intro paragraph should be set');
        my $err = "Looks like you might already have an account. Need to reset your password?\n   ";
        $tx->is('./p[@class="error"]', $err, '... Error paragraph should be set');

        # Check the form fields.
        $tx->ok('./form[@id="reqform"]/fieldset[1]', '... Check first fieldset', sub {
            $tx->is('./input[@id="name"]/@value', 'Tom Lane', '...... Name should be set');
            $tx->is('./input[@id="email"]/@value', '', '...... Email should be blank');
            $tx->is('./input[@id="uri"]/@value', 'http://tgl.example.org/', '...... URI should be set');
            $tx->is('./input[@id="nickname"]/@value', 'yodude', '...... Nickname should be set');
        });

        $tx->ok('./form[@id="reqform"]/fieldset[2]', '... Check second fieldset', sub {
            $tx->is(
                './textarea[@id="why"]',
                'In short, +1 from me. Regards, Tom Lane',
                '...... Why textarea should be set'
            );
        });
    });
};

# Start a new test transaction and post with missing data.
TxnTest->restart;
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(POST '/register', [
        name     => '',
        email    => '',
        uri      => '',
        nickname => '',
        why      => '',
    ]), 'POST empty form to /register yet again';
    ok !$res->is_redirect, 'It should not be a redirect response';
    is $res->code, 409, 'Should have 409 status code';

    # So check the content.
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    XPathTest->test_basics($tx, $req, $mt, {
        desc        => $desc,
        keywords    => $keywords,
        h1          => $h1,
    });

    # Now verify that we have the error message.
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 4, '... It should have four subelements');
        $tx->is('./h1', $h1, '... The title h1 should be set');
        $tx->is('./p[1]', $p, '... Intro paragraph should be set');
        my $err = $mt->maketext('Sorry, the nickname “[_1]” is invalid. Your nickname must start with a letter, end with a letter or digit, and otherwise contain only letters, digits, or hyphen. Sorry to be so strict.', '');
        $tx->is('./p[@class="error"]', $err, '... Error paragraph should be set');
    });
};

# Try a bogus nickname.
TxnTest->restart;
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(POST '/register', [
        name     => '',
        email    => '',
        uri      => '',
        nickname => '-@@-',
        why      => '',
    ]), 'POST empty form to /register yet again';
    ok !$res->is_redirect, 'It should not be a redirect response';
    is $res->code, 409, 'Should have 409 status code';

    # So check the content.
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    XPathTest->test_basics($tx, $req, $mt, {
        desc        => $desc,
        keywords    => $keywords,
        h1          => $h1,
    });

    # Now verify that we have the error message.
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 4, '... It should have four subelements');
        $tx->is('./h1', $h1, '... The title h1 should be set');
        $tx->is('./p[1]', $p, '... Intro paragraph should be set');
        my $err = $mt->maketext('Sorry, the nickname “[_1]” is invalid. Your nickname must start with a letter, end with a letter or digit, and otherwise contain only letters, digits, or hyphen. Sorry to be so strict.', '-@@-');
        $tx->is('./p[@class="error"]', $err, '... Error paragraph should be set');
        $tx->ok('./form/fieldset[1]/input[@id="nickname"]', '... Test nickname input', sub {
            $tx->is('./@value', '', '...... Its value should be empty');
        })
    });
};

# Try a bogus email.
TxnTest->restart;
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(POST '/register', [
        name     => '',
        email    => 'getme at whatever dot com',
        uri      => '',
        nickname => 'foo',
        why      => '',
    ]), 'POST empty form to /register yet again';
    ok !$res->is_redirect, 'It should not be a redirect response';
    is $res->code, 409, 'Should have 409 status code';

    # So check the content.
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    XPathTest->test_basics($tx, $req, $mt, {
        desc        => $desc,
        keywords    => $keywords,
        h1          => $h1,
    });

    # Now verify that we have the error message.
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 4, '... It should have four subelements');
        $tx->is('./h1', $h1, '... The title h1 should be set');
        $tx->is('./p[1]', $p, '... Intro paragraph should be set');
        my $err = $mt->maketext(q{Hrm, “[_1]” doesn't look like an email address. Care to try again?}, 'getme at whatever dot com');
        $tx->is('./p[@class="error"]', $err, '... Error paragraph should be set');
        $tx->ok('./form/fieldset[1]/input[@id="email"]', '... Test email input', sub {
            $tx->is('./@value', '', '...... Its value should be empty');
        })
    });
};

# Try a bogus uri.
TxnTest->restart;
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(POST '/register', [
        name     => '',
        uri      => 'http:\\foo.com/',
        email    => 'foo@bar.com',
        nickname => 'foo',
        why      => '',
    ]), 'POST empty form to /register yet again';
    ok !$res->is_redirect, 'It should not be a redirect response';
    is $res->code, 409, 'Should have 409 status code';

    # So check the content.
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    XPathTest->test_basics($tx, $req, $mt, {
        desc        => $desc,
        keywords    => $keywords,
        h1          => $h1,
    });

    # Now verify that we have the error message.
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 4, '... It should have four subelements');
        $tx->is('./h1', $h1, '... The title h1 should be set');
        $tx->is('./p[1]', $p, '... Intro paragraph should be set');
        my $err = $mt->maketext(q{Hrm, “[_1]” doesn't look like a URI. Care to try again?}, 'http:\\foo.com/');
        $tx->is('./p[@class="error"]', $err, '... Error paragraph should be set');
        $tx->ok('./form/fieldset[1]/input[@id="uri"]', '... Test uri input', sub {
            $tx->is('./@value', '', '...... Its value should be empty');
        })
    });
};