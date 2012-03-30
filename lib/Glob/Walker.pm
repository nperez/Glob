
sub run_walker {
    my $dist_rule = Path::Class::Rule->new->file->iname(
        '*.tar', qr'\.tar[._-]gz$', '*.tgz', '*.tar.bz2', '*.tbz', '*.tar.Z', '*.zip',
    );

    my $next = $dist_rule->iter($backpan->subdir('authors'), {
        follow_symlinks =>  0,
        depthfirst      => -1,
    });

    my $ctx = ZeroMQ::Context->new;
    my $pushsock = $ctx->socket(ZMQ_PUSH);
    $pushsock->bind($ipc_path);
    $pushsock->setsockopt(ZMQ_HWM, 32);

    warn "walking dists";
    while (my $abs_file = $next->()) {
        my $cpan_file = $abs_file->relative($backpan);
        my $dist = CPAN::DistnameInfo->new($cpan_file);
        my $normalised_distname = join '/' => map { $dist->$_ } qw(cpanid filename);

        next if exists $existing_refs{ $normalised_distname };
        $pushsock->send(encode_json {
            action => 'store_dist',
            dist   => {
                cpan_file       => $cpan_file->stringify,
                local_file      => $backpan->file($cpan_file)->stringify,
                normalised_name => $normalised_distname,
            },
        });
    }

    warn "DONE!";
}
