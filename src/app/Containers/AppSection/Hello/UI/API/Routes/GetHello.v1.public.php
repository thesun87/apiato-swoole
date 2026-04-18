<?php

use App\Containers\AppSection\Hello\UI\API\Controllers\GetHelloController;
use Illuminate\Support\Facades\Route;

Route::get('hello', GetHelloController::class)
    ->name('api_hello_get_hello');
