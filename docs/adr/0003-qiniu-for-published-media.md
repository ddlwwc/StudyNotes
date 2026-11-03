# 发布媒体使用七牛云存储

Status: extended by ADR-0021; private note media also uses Qiniu under a separate namespace.

Web 发布站的结构化正文、元数据和资源引用保存在 MySQL，发布文章的图片与静态资源保存在七牛云的私有 Bucket。发布时只有 Mac 能通过 Web 服务签发的短时上传凭据写入媒体，读者通过 Web 服务生成的短时签名 URL 读取媒体，永久七牛云密钥只保存在服务器。这样可避免数据库膨胀、阻止直接遍历资源，并限制移动端的写权限，但发布媒体的可用性会依赖七牛云这一外部服务。
