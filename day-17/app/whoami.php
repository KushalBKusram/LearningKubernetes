<?php
// Plain-text answer for scripts: "<image version> <task hostname>".
header('Content-Type: text/plain');
echo (getenv('APP_VERSION') ?: 'unknown') . ' ' . gethostname() . "\n";
