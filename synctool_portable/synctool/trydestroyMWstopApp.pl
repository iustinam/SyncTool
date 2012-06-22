 #!/usr/bin/perl -w
    use Tk;
    use strict;

    my $mw = MainWindow->new;
    fill_window($mw, 'Main');
    my $top1 = $mw->Toplevel;
    fill_window($top1, 'First top-level');
    my $top2 = $mw->Toplevel;
    fill_window($top2, 'Second top-level');
    MainLoop;

    sub fill_window {
        my ($window, $header) = @_;
        $window->Label(-text => $header)->pack;
        $window->Button(
            -text    => 'close',
            -command => [$window => 'destroy']
        )->pack(-side => 'left');
        $window->Button(
            -text    => 'exit',
            -command => [$mw => 'destroy']
        )->pack(-side => 'right');
    }