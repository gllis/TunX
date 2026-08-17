//
//  SecurityScopedBookmark.swift
//  TunX
//
//  Created by liguilong on 2026/8/13.
//

import Foundation

enum BookmarkError: Error, LocalizedError {
    case stale
    case creationFailed(Error)
    case resolutionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .stale:
            return "文件书签已过期，请重新选择私钥文件"
        case .creationFailed(let error):
            return "创建文件书签失败: \(error.localizedDescription)"
        case .resolutionFailed(let error):
            return "解析文件书签失败: \(error.localizedDescription)"
        }
    }
}

struct SecurityScopedBookmark {
    static func create(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw BookmarkError.creationFailed(error)
        }
    }

    static func resolve(_ data: Data) throws -> URL {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                throw BookmarkError.stale
            }
            return url
        } catch {
            throw BookmarkError.resolutionFailed(error)
        }
    }
}

func realHomeDirectory() -> String {
    let containerHome = NSHomeDirectory()
    guard let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir else {
        return containerHome
    }
    return String(cString: dir)
}
