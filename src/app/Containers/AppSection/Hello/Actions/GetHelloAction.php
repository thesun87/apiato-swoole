<?php

namespace App\Containers\AppSection\Hello\Actions;

use App\Ship\Parents\Actions\Action;

class GetHelloAction extends Action
{
    public function run(): string
    {
        return 'Hello from Apiato + Swoole!';
    }
}
