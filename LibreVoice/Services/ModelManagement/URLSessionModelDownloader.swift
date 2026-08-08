//
//  URLSessionModelDownloader.swift
//  LibreVoice
//

import Foundation

/// Downloads one file over HTTPS with `URLSession`, reporting progress.
///
/// This is the only type in LibreVoice that opens a network connection, so its security
/// posture is deliberate and narrow:
///
/// - **HTTPS only.** A non-HTTPS source is refused before a request is made, and a
///   redirect that tries to downgrade to HTTP is refused mid-flight. A model is code the
///   engine will trust; it may not arrive over a channel anyone on the path can rewrite.
/// - **No user data, no footprint.** The session is ephemeral: no cookies, no disk cache,
///   no credential storage. A download carries the URL and nothing else — no audio, no
///   transcript, no identifier. There is nothing here to phone home with.
/// - **TLS is the system's.** No custom authentication-challenge handling, so App
///   Transport Security and the system trust store validate the certificate. LibreVoice
///   does not weaken that.
///
/// Integrity (the checksum) is *not* checked here — that is the repository's job, once the
/// file is on disk. This type only guarantees the bytes arrived over a sound channel.
nonisolated final class URLSessionModelDownloader: ModelFileDownloading {
    private let logger: any Logger

    init(logger: any Logger = NullLogger()) {
        self.logger = logger
    }

    func download(
        from url: URL,
        expectedSize: Int64?,
        onProgress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws -> URL {
        guard url.scheme?.lowercased() == "https" else {
            logger.error("Refused a non-HTTPS model URL.", category: .speech)
            throw ModelError.insecureURL(url)
        }

        let delegate = DownloadDelegate(expectedSize: expectedSize, onProgress: onProgress, logger: logger)

        // Ephemeral: nothing about this download is persisted anywhere.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.begin(session: session, url: url, continuation: continuation)
            }
        } onCancel: {
            delegate.cancel()
        }
    }
}

/// Bridges `URLSession`'s delegate callbacks into one `async` result.
///
/// `URLSession` calls these methods serially on its own queue, so the only real race is
/// between a delegate callback and `cancel()` arriving from another task — handled by
/// resolving the continuation in exactly one place (`didCompleteWithError`) and guarding
/// it with a lock.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let expectedSize: Int64?
    private let onProgress: @Sendable (ModelDownloadProgress) -> Void
    private let logger: any Logger

    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, any Error>?
    private var task: URLSessionDownloadTask?

    /// Where the finished file was moved to, since the delegate's own temp file is
    /// deleted the moment `didFinishDownloadingTo` returns.
    private var stagedURL: URL?

    /// Set when the transfer was stopped for exceeding its declared size.
    ///
    /// Needed because stopping it means cancelling the task, and a cancelled task is
    /// otherwise indistinguishable from the user pressing Cancel — which would report a
    /// server sending more than it should as a routine cancellation and tell nobody.
    private var refusedAsOversize = false

    init(
        expectedSize: Int64?,
        onProgress: @escaping @Sendable (ModelDownloadProgress) -> Void,
        logger: any Logger
    ) {
        self.expectedSize = expectedSize
        self.onProgress = onProgress
        self.logger = logger
    }

    func begin(session: URLSession, url: URL, continuation: CheckedContinuation<URL, any Error>) {
        lock.lock()
        self.continuation = continuation
        let task = session.downloadTask(with: url)
        self.task = task
        lock.unlock()
        task.resume()
    }

    func cancel() {
        lock.lock()
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        // Stop a server that sends more than the catalog said it would.
        //
        // The checksum is the real integrity check, but it only runs once the file is on
        // disk — so without a ceiling, a compromised or hostile mirror could stream
        // gigabytes into the temporary directory and fill the volume before anything
        // noticed. The catalog states an exact size per file; anything past it is already
        // wrong, whatever the reason, and there is nothing to gain by receiving the rest.
        if DownloadSizeLimit.isOversize(received: totalBytesWritten, expected: expectedSize) {
            logger.error(
                "A model file exceeded its declared size; the download was stopped.",
                category: .speech
            )
            lock.lock()
            refusedAsOversize = true
            lock.unlock()
            cancel()
            return
        }

        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedSize
        onProgress(ModelDownloadProgress(bytesReceived: totalBytesWritten, totalBytes: total))
    }


    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The HTTP status is only meaningful here, and a 404/403 still "finishes" with an
        // error page as its body — which would sail through as a corrupt file if not
        // caught. It would fail the checksum later regardless, but failing now is clearer.
        if let response = downloadTask.response as? HTTPURLResponse, !(200...299).contains(response.statusCode) {
            logger.error("Model file request returned HTTP \(response.statusCode).", category: .speech)
            return // `stagedURL` stays nil → didComplete reports the failure.
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("librevoice-download-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            lock.lock()
            stagedURL = destination
            lock.unlock()
        } catch {
            logger.error("Couldn't stage a downloaded model file.", error: error, category: .speech)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        lock.lock()
        guard let continuation else { lock.unlock(); return }
        self.continuation = nil
        let staged = stagedURL
        let oversize = refusedAsOversize
        lock.unlock()

        if oversize {
            continuation.resume(throwing: ModelError.downloadFailed(
                reason: String(localized: "the server sent more data than the model's declared size")
            ))
        } else if let error {
            let urlError = error as? URLError
            if urlError?.code == .cancelled {
                continuation.resume(throwing: ModelError.cancelled)
            } else {
                continuation.resume(throwing: ModelError.downloadFailed(reason: error.localizedDescription))
            }
        } else if let staged {
            continuation.resume(returning: staged)
        } else {
            continuation.resume(throwing: ModelError.downloadFailed(reason: "the server response was not usable"))
        }
    }

    // MARK: - Redirect safety

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Hugging Face redirects to a CDN, so redirects are expected — but only to HTTPS.
        // A redirect to http:// is a downgrade attack and is refused by passing nil,
        // which cancels the redirect and fails the task.
        guard request.url?.scheme?.lowercased() == "https" else {
            logger.error("Refused an insecure redirect during a model download.", category: .speech)
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
