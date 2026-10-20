<?php

require __DIR__.'/vendor/autoload.php';

return Flarum\Foundation\Site::fromPaths([
    'base' => __DIR__,
    'public' => __DIR__.'/public',
    'storage' => '/data/storage',
]);
