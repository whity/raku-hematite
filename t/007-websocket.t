#!/usr/bin/env raku

use Test;
use HTTP::Server::Tiny;
use WebSocket::P6W;
use WebSocket::Client;
use Hematite;
use Logger;

sub MAIN {
    plan(5);

    my $port = 15555;

    start {
        my $server = HTTP::Server::Tiny.new(port => $port);
        my $app    = Hematite.new;

        $app.WS('/', sub ($ctx) {
            $ctx.on('ready', sub {
                ok(True, 'server: ready');
            });

            $ctx.on('message', sub ($txt) {
                is($txt, 'STEP1', 'server: text');
                $ctx.send('message', 'STEP2');
            });

            $ctx.on('close', sub {
                ok(True, 'server: closed');
            });
        });

        $server.run($app);
    };

    wait-port($port);

    await Promise.anyof(
        start {
             WebSocket::Client.connect(
                "ws://127.0.0.1:$port/",
                on-text => -> $h, $txt {
                    is($txt, 'STEP2', 'client: text');
                    $h.send-close;
                },
                on-ready => -> $h {
                    ok(True, 'client: ready');

                    sleep 0.1;

                    $h.send-text("STEP1");
                },
            )
        },
        Promise.in(5).then( { fail "Test timed out!" } ),
    );
}

sub wait-port(Int $port) {
    LOOP: for 1..100 {
        try {
            my $sock = IO::Socket::INET.new(
                host => '127.0.0.1',
                port => $port,
            );

            $sock.close;

            return;

            CATCH {
                sleep 0.1;
                next LOOP;
            }
        }
    }

    die "127.0.0.1:$port doesn't open in 0.1*100 sec.";
}
