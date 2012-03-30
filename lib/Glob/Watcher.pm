
sub run_watcher {
    my $watcher_pid = $$;

    run_fork {
        child {
            try {
                $0 = 'walker';
                run_walker();
            }
            catch {
                die "walked exited: $_";
            }
            finally {
                #kill SIGTERM, $watcher_pid;
            };

            exit 0;
        }
        parent {
            $0 = 'watcher';

            my $pm = Parallel::Prefork->new({
                max_workers => 16,
            });

            while ($pm->signal_received ne 'TERM') {
                $pm->start(sub {
                    warn "spawning new worker";
                    try {
                        $0 = 'unpacker';
                        run_unpacker();
                    }
                    catch {
                        die "worker exited abnormally: $_";
                    };
                });
            }

            $pm->wait_all_children;
            warn "all done";
            exit 0;
        }
    };
}
