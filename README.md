wacker
======

Wraper script for Packer

## Description

Creates temporary vpc and subnet on AWS for packer build process, and also removes the garbages.

## Requirements

* [Packer](https://www.packer.io/)
* [awscli](https://aws.amazon.com/cli/)
* [jq](https://stedolan.github.io/jq/)

## Install

Use your favorite zsh plugin manager. If you use [antibody](https://github.com/getantibody/antibody), paste below code to your `~/.zshrc`:

```bash
antibody bundle knakayama/wacker
```

## Usage

First, configure your awscli with [this instructions](http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-set-up.html), and write your packer template. Wacker provides `vpc_id` and `subnet_id` variables, so you must specify this variables in your packer template like this.

```json
{
  "variables": {
    "vpc_id":    "vpc_id",
    "subnet_id": "subnet_id",
    ...
  },
  "builders": [
    {
      "vpc_id":    "{{user `vpc_id`}}",
      "subnet_id": "{{user `subnet_id`}}",
      ...
    }
  ]
}
```

These instructions are completed, just enter `wacker <your-packer-template>`.

## License

MIT

## Author

[knakayama](https://github.com/knakayama)
