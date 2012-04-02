#!/usr/bin/perl -I/home/ccm_root/perl/modules_P5

use strict;
use warnings;
use MIME::Lite;

my $file_contents;
open FILE, "<clone.pl";
$file_contents = do { local $/; <FILE> };
close FILE;


my $from_address = 'ccm_root@continental-corporation.com';
my $to_addr='Iustina.2.Melinte@continental-corporation.com';

my $mail_host = 'smtphub07.conti.de';

my $msg = MIME::Lite->new (
        From => $from_address,
        To => 'iustina.m.90@gmail.com',
        Cc=> 'Iustina.2.Melinte@continental-corporation.com,adrian.damian@continental-corporation.com',
        Subject => "Synctool Notification",
        Type =>'multipart/mixed'
)or die "Error creating multipart container: $!\n";

$msg->attach (
        Type => 'TEXT',
        Data => $file_contents
)or die "Error adding the text message part: $!\n";


MIME::Lite->send('smtp', $mail_host, Timeout=>60);

$msg->send;
