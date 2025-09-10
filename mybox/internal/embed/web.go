package embed

import (
    "embed"
    "io/fs"
    "net/http"
)

//go:embed web
var webFS embed.FS

// GetWebFS 返回Web文件系统
func GetWebFS() http.FileSystem {
    webRoot, err := fs.Sub(webFS, "web")
    if err != nil {
        panic(err)
    }
    return http.FS(webRoot)
}