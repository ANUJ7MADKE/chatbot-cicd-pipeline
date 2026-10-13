# AWS Lambda Web Adapter 0.9.1 (linux/amd64)

`lambda-adapter` is the unmodified binary from the official image
`public.ecr.aws/awsguru/aws-lambda-adapter:0.9.1`
(source: https://github.com/awslabs/aws-lambda-web-adapter, Apache-2.0 license).

It is committed here instead of being pulled during the build because the public
registry rate-limits anonymous pulls from shared CI runners, which made builds fail
at random. The Dockerfile verifies this SHA-256 before using the file:

    f4c9748d551878ddd4e612457bb23b869e0a47a53d14e66ed6cab1fd1f797699  lambda-adapter

To upgrade: copy `/lambda-adapter` out of the new image version (linux/amd64),
replace this file, and update the checksum here and in the Dockerfile.
