# Spring Boot 托管前端静态资源（单容器全栈）——完整代码与坑位解释

## 为什么会有三个坑

Spring Boot 自带的静态资源机制默认只查 classpath（`classpath:/static` 等）。要把**文件系统目录**（容器里的 dist）挂到 `/**`，用 `addResourceHandlers` 挂 `file:` location 时，有三个不查文档必踩的坑：

1. **根路径 `/` 被 welcome-page 映射抢占**：`WelcomePageHandlerMapping` 只在 classpath 位置找 `index.html`，找不到就 404，且它的优先级高于自定义 `/**` 资源处理器。解法是 `addViewControllers("/")` 显式 forward 到 `/index.html`——显式注册的 controller 优先级高于 welcome-page。
2. **空路径/目录资源**：请求 `/` 时资源路径是空串，`createRelative("")` 返回的是**目录**资源（非 null 但不是文件），直接返回会让 `ResourceHttpRequestHandler` 抛 `NoResourceFoundException`。所以 resolver 里要把空路径映射成 `index.html`，并用 `res.getFile().isFile()` 复核。
3. **404 语义被兜底 500 吞掉**：资源未命中抛的 `NoResourceFoundException` 会被"包一层 `@ExceptionHandler(Exception.class)`"的全局异常处理器接住返回 500。要单独给它映射 404；同时 SPA 回退必须排除 `api/` 前缀，否则接口 404 也变成 HTML。

## 完整代码

```java
@Configuration
public class StaticWebConfig implements WebMvcConfigurer {

    private final String staticDir;

    public StaticWebConfig(@Value("${app.static-dir:}") String staticDir) {
        this.staticDir = staticDir == null ? "" : staticDir.trim();
    }

    @Override
    public void addViewControllers(ViewControllerRegistry registry) {
        // 显式接管 "/"（Boot 默认 welcome-page 只查 classpath，会 404）
        registry.addViewController("/").setViewName("forward:/index.html");
    }

    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        if (staticDir.isEmpty()) {
            return; // 本地开发走 vite dev server，不配置即不启用
        }
        String location = staticDir.endsWith("/") ? staticDir : staticDir + "/";
        registry.addResourceHandler("/**")
                .addResourceLocations("file:" + location)
                .setCachePeriod(3600)
                .resourceChain(true)
                .addResolver(new PathResourceResolver() {
                    @Override
                    protected Resource getResource(String resourcePath, Resource location) throws IOException {
                        if (resourcePath.isEmpty()) {
                            resourcePath = "index.html"; // 空路径会被解析成目录资源
                        }
                        Resource res = super.getResource(resourcePath, location);
                        if (res != null && res.getFile().isFile()) {
                            return res;
                        }
                        if (resourcePath.startsWith("api/")) {
                            return null; // 接口 404 保持 404，不回退 HTML
                        }
                        return location.createRelative("index.html"); // SPA 回退
                    }
                });
    }
}
```

## application.yml 配套

```yaml
server:
  port: 8080
  compression:
    # 替代 nginx 的 gzip：静态资源与 JSON 响应压缩
    enabled: true
    mime-types: text/html,text/css,application/javascript,application/json
    min-response-size: 1KB

app:
  # 用占位符显式映射环境变量；不要依赖 relaxed binding：
  # APP_STATIC_DIR 不会映射到 app.static-dir（连字符会被去掉）
  static-dir: ${STATIC_DIR:}
```

## 验证清单（部署后逐条 curl）

```bash
curl -s http://localhost:8080/ | head -3                 # 返回 <!doctype html>（不是 {"message":...}）
JS=$(curl -s http://localhost:8080/ | grep -o 'assets/index-[^"]*\.js' | head -1)
curl -s -o /dev/null -w "%{http_code} %{size_download}B\n" http://localhost:8080/$JS   # 200，且体积明显小于源文件（gzip 生效）
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/some/route              # 200（SPA 回退）
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/api/notexist            # 404（接口语义不被吞）
```

## 取舍备忘

- 该方案适合单实例 demo/小项目；**多实例、需要 TLS、大流量静态资源**时拆回 nginx 前置（应用只暴露 8080，nginx 反代 + 静态 + TLS）。
- Spring Boot 静态服务的缓存头较弱（`setCachePeriod`），带内容 hash 的 assets 路径可设长缓存：需要时把 `assets/**` 单独注册一个 handler 设 `setCachePeriod(31536000)`。
