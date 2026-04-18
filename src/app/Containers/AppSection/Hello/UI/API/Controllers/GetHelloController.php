<?php

namespace App\Containers\AppSection\Hello\UI\API\Controllers;

use App\Containers\AppSection\Hello\Actions\GetHelloAction;
use App\Ship\Parents\Controllers\ApiController;

class GetHelloController extends ApiController
{
    public function __invoke(): array
    {
        $message = app(GetHelloAction::class)->run();

        return ['message' => $message];
    }
}
