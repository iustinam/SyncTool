use Tk;
use Tk::NoteBook;

$mw = MainWindow->new();
$mw->geometry( "400x100" );
$book = $mw->NoteBook()->pack( -fill=>'both', -expand=>1 );

$tab1 = $book->add( "Sheet 1", -label=>"Start", -createcmd=>\&getStartTime );
$tab2 = $book->add( "Sheet 2", -label=>"Continue", -raisecmd=>\&getCurrentTime );
$tab3 = $book->add( "Sheet 3", -label=>"End", -state=>'disabled' );

$tab1->Label( -textvariable=>\$starttime )->pack(  );
$tab2->Label( -textvariable=>\$raisetime )->pack(  );
$tab3->Button( -text=>'Quit', -command=>sub{ exit; } )->pack( );

MainLoop;

sub getStartTime {
  $starttime = "Started at " . localtime;
}

sub getCurrentTime {
  $raisetime = " Last raised at " . localtime;
  $book->pageconfigure( "Sheet 3", -state=>'normal' );
}