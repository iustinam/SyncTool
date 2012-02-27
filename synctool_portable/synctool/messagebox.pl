#!/usr/local/bin/perl
use Tk;
use strict;

# Main Window
my $mw = new MainWindow;
my $button = $mw->Button(-text=>"Show Quit Dailog", -command => \&exitTheApp)->pack();

sub exitTheApp {
	my $response = $mw -> messageBox(-message=>"Really quit?",-type=>'yesno',-icon=>'question');
	
	if( $response eq "Yes" ) {
		exit
	} else {
		$mw -> messageBox(-type=>"ok", -message=>"I know you like this application!");
	}
}

MainLoop;