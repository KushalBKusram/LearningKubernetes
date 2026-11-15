<?php
// The chapter's project (slide 329): an image upload form in PHP, no database.
// The uploaded files are stored next to this script, in uploads/. Both live on
// the shared volume, so every task of the service sees the same files.

$dir = __DIR__ . '/uploads';
$allowed = [
    'image/jpeg' => 'jpg',
    'image/png'  => 'png',
    'image/gif'  => 'gif',
    'image/webp' => 'webp',
];
$message = '';

header('X-Served-By: ' . gethostname());

if (!is_dir($dir)) {
    @mkdir($dir, 0755);
}
// Uploaded files are data. Never let the web server run one as PHP.
if (is_dir($dir) && !file_exists("$dir/.htaccess")) {
    @file_put_contents("$dir/.htaccess", "php_flag engine off\n");
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $file = $_FILES['image'] ?? null;
    if (!$file || $file['error'] !== UPLOAD_ERR_OK) {
        http_response_code(400);
        $message = 'The upload failed.';
    } else {
        // Decide by the file's content, not by the name the browser sent.
        $info = @getimagesize($file['tmp_name']);
        $mime = $info['mime'] ?? '';
        if (!isset($allowed[$mime])) {
            http_response_code(415);
            $message = 'Only JPEG, PNG, GIF and WebP images are accepted.';
        } else {
            $name = bin2hex(random_bytes(8)) . '.' . $allowed[$mime];
            if (move_uploaded_file($file['tmp_name'], "$dir/$name")) {
                chmod("$dir/$name", 0644);
                header("X-Stored-As: $name");
                $message = "Stored as $name.";
            } else {
                http_response_code(500);
                $message = 'The file could not be stored.';
            }
        }
    }
}

$images = [];
foreach (scandir($dir) ?: [] as $entry) {
    if (preg_match('/\.(jpg|png|gif|webp)$/', $entry)) {
        $images[] = $entry;
    }
}
?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Day 18: memories</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <main>
    <h1>Memories</h1>
    <p class="meta">Answered by task <code><?= htmlspecialchars(gethostname()) ?></code>.
       Reload: the task changes, the pictures stay.</p>

    <form method="post" enctype="multipart/form-data">
      <label for="image">Add a picture</label>
      <input type="file" id="image" name="image" accept="image/*" required>
      <button type="submit">Upload</button>
    </form>
    <?php if ($message !== ''): ?>
      <p class="message"><?= htmlspecialchars($message) ?></p>
    <?php endif; ?>

    <h2><?= count($images) ?> stored</h2>
    <ul class="gallery">
      <?php foreach ($images as $image): ?>
        <li><img src="uploads/<?= htmlspecialchars($image) ?>" alt="<?= htmlspecialchars($image) ?>" loading="lazy"></li>
      <?php endforeach; ?>
    </ul>
  </main>
</body>
</html>
