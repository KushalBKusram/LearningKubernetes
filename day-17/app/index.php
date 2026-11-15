<?php
$version = getenv('APP_VERSION') ?: 'unknown';
$task = gethostname();
?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Day 17: a service with several tasks</title>
  <style>
    :root { color-scheme: light dark; }
    body { margin: 0; font-family: system-ui, sans-serif; line-height: 1.5; }
    main { max-width: 40rem; margin: 4rem auto; padding: 0 1rem; }
    dt { font-weight: 600; margin-top: 1rem; }
    dd { margin: 0; font-family: ui-monospace, monospace; }
  </style>
</head>
<body>
  <main>
    <h1>Day 17: a service with several tasks</h1>
    <p>Reload a few times. The task changes, because the service spreads
       requests over all of its running tasks.</p>
    <dl>
      <dt>Image version</dt>
      <dd><?= htmlspecialchars($version) ?></dd>
      <dt>Answered by task (container hostname)</dt>
      <dd><?= htmlspecialchars($task) ?></dd>
    </dl>
  </main>
</body>
</html>
