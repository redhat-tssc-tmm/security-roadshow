## Web Terminal based on `ttyd`

The OpenShift Terminal used in the PE Workshop is a bit unstable, with students losing their context and environment variables when the connection resets.

This is based on the [ttyd](https://github.com/tsl0922/ttyd) open source project, built with the [1.7.7 release binary](https://github.com/tsl0922/ttyd/releases/tag/1.7.7) on a UBI9 base image

Thank you [Shuanglei Tao](https://github.com/tsl0922) 💚

The image can be found at [Quay.io](https://quay.io/repository/tssc_demos/ttyd-admin-terminal?tab=tags)