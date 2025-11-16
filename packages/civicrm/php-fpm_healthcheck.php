<?php
// Read arguments from temporary file
$args = file_get_contents('/tmp/healthcheck.args');
list($socketType, $listen, $pingPath, $pong) = explode(' ', trim($args));

$fcgi = @stream_socket_client($socketType . "://" . $listen, $errno, $errstr, 1);
if (!$fcgi) {
    fwrite(STDERR, "ERROR: Cannot connect to PHP-FPM socket: $errstr ($errno)\n");
    exit(1);
}

/**
 * FastCGI protocol constants
 */
define('FCGI_VERSION_1', 1);
define('FCGI_BEGIN_REQUEST', 1);
define('FCGI_PARAMS', 4);
define('FCGI_STDIN', 5);

function fcgi_record($type, $content, $requestId = 1) {
    $len = strlen($content);
    $pad = ($len % 8) ? 8 - ($len % 8) : 0;
    return pack('CCnnCC', FCGI_VERSION_1, $type, $requestId, $len, $pad, 0)
        . $content
        . str_repeat("\x00", $pad);
}

// BEGIN_REQUEST
$begin = pack('nC6', 1, 0, 0, 0, 0, 0, 0);
$packet = fcgi_record(FCGI_BEGIN_REQUEST, $begin);

// Minimal environment
$params = [
    'SCRIPT_FILENAME' => '/var/www/html/index.php',
    'SCRIPT_NAME'     => $pingPath,
    'REQUEST_METHOD'  => 'GET',
    'SERVER_PROTOCOL' => 'HTTP/1.1',
];
foreach ($params as $k => $v) {
    $packet .= fcgi_record(FCGI_PARAMS, chr(strlen($k)) . chr(strlen($v)) . $k . $v);
}
// End of PARAMS and STDIN
$packet .= fcgi_record(FCGI_PARAMS, '');
$packet .= fcgi_record(FCGI_STDIN, '');

// Send and read response
fwrite($fcgi, $packet);
$response = stream_get_contents($fcgi, 8192);
fclose($fcgi);

// Check for FastCGI response
if ($response === false || strlen($response) === 0) {
    fwrite(STDERR, "PHP-FPM did not respond\n");
    exit(1);
}

// Check for correct response
if (strpos($response, $pong) !== false) {
    exit(0);
}

fwrite(STDERR, "Invalid PHP-FPM response\n");
exit(1);
