const http = require('http')
const fs = require('fs')
const path = require('path')

const PORT = 3000

const mimeTypes = {
    '.html': 'text/html',
    '.js': 'application/javascript',
    '.mjs': 'application/javascript',
    '.css': 'text/css',
    '.json': 'application/json',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
    '.svg': 'image/svg+xml',
    '.ico': 'image/x-icon',
    '.woff': 'font/woff',
    '.woff2': 'font/woff2',
    '.txt': 'text/plain',
}

function serveDirectory(dirPath, urlPath, res) {
    fs.readdir(dirPath, { withFileTypes: true }, (err, entries) => {
        if (err) {
            res.writeHead(500)
            res.end('Internal Server Error')
            return
        }
        const rows = entries.map(e => {
            const href = urlPath.replace(/\/$/, '') + '/' + e.name + (e.isDirectory() ? '/' : '')
            return `<li><a href="${href}">${e.name}${e.isDirectory() ? '/' : ''}</a></li>`
        }).join('\n')
        res.writeHead(200, { 'Content-Type': 'text/html' })
        res.end(`<!DOCTYPE html><html><body><h2>${urlPath}</h2><ul>${rows}</ul></body></html>`)
    })
}

http.createServer((req, res) => {
    const urlPath = decodeURIComponent(req.url.split('?')[0])
    const filePath = path.join(__dirname, urlPath)

    fs.stat(filePath, (err, stat) => {
        if (err) {
            res.writeHead(404)
            res.end('Not Found')
            return
        }

        if (stat.isDirectory()) {
            const indexPath = path.join(filePath, 'index.html')
            fs.access(indexPath, fs.constants.F_OK, accessErr => {
                if (accessErr) {
                    serveDirectory(filePath, urlPath, res)
                } else {
                    fs.readFile(indexPath, (readErr, data) => {
                        if (readErr) { res.writeHead(500); res.end('Error'); return }
                        res.writeHead(200, { 'Content-Type': 'text/html' })
                        res.end(data)
                    })
                }
            })
            return
        }

        const ext = path.extname(filePath)
        const contentType = mimeTypes[ext] || 'application/octet-stream'
        fs.readFile(filePath, (readErr, data) => {
            if (readErr) { res.writeHead(500); res.end('Error'); return }
            res.writeHead(200, { 'Content-Type': contentType })
            res.end(data)
        })
    })
}).listen(PORT, () => {
    console.log(`서버 실행 중: http://localhost:${PORT}`)
})
