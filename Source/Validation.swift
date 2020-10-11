//
//  Validation.swift
//
//  Copyright (c) 2014-2018 Alamofire Software Foundation (http://alamofire.org/)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

// MARK: Comment start

import Foundation

/// 对 Alamofire 里面的 Request 对象的扩展。
extension Request {
    // MARK: Helper Types

    /// 定义一个当前文件私有的 typealias 别名的意义在于内部含义更精简
    fileprivate typealias ErrorReason = AFError.ResponseValidationFailureReason

    /// Used to represent whether a validation succeeded or failed.
    /// 认证结果， Result 专门用来出来状态和错误的返回
    public typealias ValidationResult = Result<Void, Error>

    /// 内部的 MIMEType
    fileprivate struct MIMEType {
        let type: String
        let subtype: String

        /// 计算属性，返回当前是否是通配
        var isWildcard: Bool { type == "*" && subtype == "*" }

        init?(_ string: String) {
            
            let components: [String] = {
                /// 返回一个新的字符串，过滤掉空格和换行
                let stripped = string.trimmingCharacters(in: .whitespacesAndNewlines)
                /// 如果包含 ; 则返回；最后的bound，不包含则是 endIndx
                let split = stripped[..<(stripped.range(of: ";")?.lowerBound ?? stripped.endIndex)]
                    
                /// 按 / 进行分割
                return split.components(separatedBy: "/")
            }()
            
            /// type 对应第一个元素， subtype 对应最后一个
            if let type = components.first, let subtype = components.last {
                self.type = type
                self.subtype = subtype
            } else {
                return nil
            }
        }

        /// 类型是否匹配的情况，涵盖了通配符的情况
        func matches(_ mime: MIMEType) -> Bool {
            switch (type, subtype) {
            case (mime.type, mime.subtype), (mime.type, "*"), ("*", mime.subtype), ("*", "*"):
                return true
            default:
                return false
            }
        }
    }

    // MARK: Properties

    /// 可接受的状态码，只有 http 200 区间内成功的状态码
    fileprivate var acceptableStatusCodes: Range<Int> { 200..<300 }

    /// 可接收的 content 类型，从 request 对象中获取 Head 区域的 Accept ，按 , 分割进行返回，如不包含，则返回 */*
    fileprivate var acceptableContentTypes: [String] {
        if let accept = request?.value(forHTTPHeaderField: "Accept") {
            return accept.components(separatedBy: ",")
        }

        return ["*/*"]
    }

    // MARK: Status Code

    /// 验证，对 URLResponse 进行验证，返回认证结果， 序列的成员需要是 Int ，意味着是 Http status
    fileprivate func validate<S: Sequence>(statusCode acceptableStatusCodes: S,
                                           response: HTTPURLResponse)
        -> ValidationResult
        where S.Iterator.Element == Int {
        /// 序列中包含了 statusCode 则是成功的
        if acceptableStatusCodes.contains(response.statusCode) {
            return .success(())
        } else {
            /// 不成功，返回错误的AFError.ResponseValidationFailureReason.unacceptableStatusCode
            let reason: ErrorReason = .unacceptableStatusCode(code: response.statusCode)
            return .failure(AFError.responseValidationFailed(reason: reason))
        }
    }

    // MARK: Content Type

    /// 验证 data 部分，和上面不同，序列的内容是 String   
    fileprivate func validate<S: Sequence>(contentType acceptableContentTypes: S,
                                           response: HTTPURLResponse,
                                           data: Data?)
        -> ValidationResult
        where S.Iterator.Element == String {
        /// 这里走了两步
        /// 1. 数据非nil，且内容非空，不然返回一个空的成功状态
        guard let data = data, !data.isEmpty else { return .success(()) }

        /// 2. 单独进行 contentType 的验证
        return validate(contentType: acceptableContentTypes, response: response)
    }

    
    fileprivate func validate<S: Sequence>(contentType acceptableContentTypes: S,
                                           response: HTTPURLResponse)
        -> ValidationResult
        where S.Iterator.Element == String {
        guard
            /// 拿到 MIMEType 
            let responseContentType = response.mimeType,
            let responseMIMEType = MIMEType(responseContentType)
        else {
            
            /// 包含 */* 匹配的时候，返回成功
            for contentType in acceptableContentTypes {
                if let mimeType = MIMEType(contentType), mimeType.isWildcard {
                    return .success(())
                }
            }

            /// 可以接收的类型
            let error: AFError = {
                let reason: ErrorReason = .missingContentType(acceptableContentTypes: Array(acceptableContentTypes))
                return AFError.responseValidationFailed(reason: reason)
            }()

            return .failure(error)
        }

        for contentType in acceptableContentTypes {
            if let acceptableMIMEType = MIMEType(contentType), acceptableMIMEType.matches(responseMIMEType) {
                return .success(())
            }
        }

        /// 如果在 ContentType 的黑名单内，返回错误
        let error: AFError = {
            let reason: ErrorReason = .unacceptableContentType(acceptableContentTypes: Array(acceptableContentTypes),
                                                               responseContentType: responseContentType)

            return AFError.responseValidationFailed(reason: reason)
        }()

        return .failure(error)
    }
}

// MARK: -
/// DataRequest 是 Request 的子类，主要对应 DataTask，处理类似大量数据的下载任务
extension DataRequest {
    /// A closure used to validate a request that takes a URL request, a URL response and data, and returns whether the
    /// request was valid.
    /// 这里面的是一个函数， 输入 request，response， data 来验证认证结果，返回同样的上面的 Result 的结果
    /// 为的是提取一个公用的认证方法
    public typealias Validation = (URLRequest?, HTTPURLResponse, Data?) -> ValidationResult

    /// Validates that the response has a status code in the specified sequence.
    ///
    /// If validation fails, subsequent calls to response handlers will have an associated error.
    ///
    /// - Parameter statusCode: `Sequence` of acceptable response status codes.
    ///
    /// - Returns:              The instance.
    @discardableResult
    /// 级联的持续validate，返回 Self 对象，这里主要调
    /// [unowned self] 不做 weak 处理，validate 这个对象就是调用了上面的 替身 的验证方法
    /// 验证状态码
    public func validate<S: Sequence>(statusCode acceptableStatusCodes: S) -> Self where S.Iterator.Element == Int {
        validate { [unowned self] _, response, _ in
            self.validate(statusCode: acceptableStatusCodes, response: response)
        }
    }

    /// Validates that the response has a content type in the specified sequence.
    ///
    /// If validation fails, subsequent calls to response handlers will have an associated error.
    ///
    /// - parameter contentType: The acceptable content types, which may specify wildcard types and/or subtypes.
    ///
    /// - returns: The request.
    @discardableResult
    /// 验证 response
    /// @escaping @autoclosure 属性
    public func validate<S: Sequence>(contentType acceptableContentTypes: @escaping @autoclosure () -> S) -> Self where S.Iterator.Element == String {
        validate { [unowned self] _, response, data in
            self.validate(contentType: acceptableContentTypes(), response: response, data: data)
        }
    }

    /// Validates that the response has a status code in the default acceptable range of 200...299, and that the content
    /// type matches any specified in the Accept HTTP header field.
    ///
    /// If validation fails, subsequent calls to response handlers will have an associated error.
    ///
    /// - returns: The request.
    @discardableResult
    /// 验证在 http 正常的状态码返回的返回内
    public func validate() -> Self {
        let contentTypes: () -> [String] = { [unowned self] in
            self.acceptableContentTypes
        }
        return validate(statusCode: acceptableStatusCodes).validate(contentType: contentTypes())
    }
}

///  streams HTTP response 的扩展，整个扩展的功能和上面一模一样
extension DataStreamRequest {
    /// A closure used to validate a request that takes a `URLRequest` and `HTTPURLResponse` and returns whether the
    /// request was valid.
    public typealias Validation = (_ request: URLRequest?, _ response: HTTPURLResponse) -> ValidationResult

    /// Validates that the response has a status code in the specified sequence.
    ///
    /// If validation fails, subsequent calls to response handlers will have an associated error.
    ///
    /// - Parameter statusCode: `Sequence` of acceptable response status codes.
    ///
    /// - Returns:              The instance.
    @discardableResult
    public func validate<S: Sequence>(statusCode acceptableStatusCodes: S) -> Self where S.Iterator.Element == Int {
        validate { [unowned self] _, response in
            self.validate(statusCode: acceptableStatusCodes, response: response)
        }
    }

    /// Validates that the response has a content type in the specified sequence.
    ///
    /// If validation fails, subsequent calls to response handlers will have an associated error.
    ///
    /// - parameter contentType: The acceptable content types, which may specify wildcard types and/or subtypes.
    ///
    /// - returns: The request.
    @discardableResult
    public func validate<S: Sequence>(contentType acceptableContentTypes: @escaping @autoclosure () -> S) -> Self where S.Iterator.Element == String {
        validate { [unowned self] _, response in
            self.validate(contentType: acceptableContentTypes(), response: response)
        }
    }

    /// Validates that the response has a status code in the default acceptable range of 200...299, and that the content
    /// type matches any specified in the Accept HTTP header field.
    ///
    /// If validation fails, subsequent calls to response handlers will have an associated error.
    ///
    /// - Returns: The instance.
    @discardableResult
    public func validate() -> Self {
        let contentTypes: () -> [String] = { [unowned self] in
            self.acceptableContentTypes
        }
        return validate(statusCode: acceptableStatusCodes).validate(contentType: contentTypes())
    }
}

// MARK: -

/// 对应 URLSessionDownloadTask， 下载一个文件到磁盘，验证的入参不一样，是 URL ==》 data 认证
extension DownloadRequest {
    /// A closure used to validate a request that takes a URL request, a URL response, a temporary URL and a
    /// destination URL, and returns whether the request was valid.
    public typealias Validation = (_ request: URLRequest?,
                                   _ response: HTTPURLResponse,
                                   _ fileURL: URL?)
        -> ValidationResult

    /// Validates that the response has a status code in the specified sequence.
    ///
    /// If validation fails, subsequent calls to response handlers will have an associated error.
    ///
    /// - Parameter statusCode: `Sequence` of acceptable response status codes.
    ///
    /// - Returns:              The instance.
    @discardableResult
    public func validate<S: Sequence>(statusCode acceptableStatusCodes: S) -> Self where S.Iterator.Element == Int {
        validate { [unowned self] _, response, _ in
            self.validate(statusCode: acceptableStatusCodes, response: response)
        }
    }

    /// Validates that the response has a content type in the specified sequence.
    ///
    /// If validation fails, subsequent calls to response handlers will have an associated error.
    ///
    /// - parameter contentType: The acceptable content types, which may specify wildcard types and/or subtypes.
    ///
    /// - returns: The request.
    @discardableResult
    public func validate<S: Sequence>(contentType acceptableContentTypes: @escaping @autoclosure () -> S) -> Self where S.Iterator.Element == String {
        validate { [unowned self] _, response, fileURL in
            guard let validFileURL = fileURL else {
                return .failure(AFError.responseValidationFailed(reason: .dataFileNil))
            }

            do {
                let data = try Data(contentsOf: validFileURL)
                return self.validate(contentType: acceptableContentTypes(), response: response, data: data)
            } catch {
                return .failure(AFError.responseValidationFailed(reason: .dataFileReadFailed(at: validFileURL)))
            }
        }
    }

    /// Validates that the response has a status code in the default acceptable range of 200...299, and that the content
    /// type matches any specified in the Accept HTTP header field.
    ///
    /// If validation fails, subsequent calls to response handlers will have an associated error.
    ///
    /// - returns: The request.
    @discardableResult
    public func validate() -> Self {
        let contentTypes = { [unowned self] in
            self.acceptableContentTypes
        }
        return validate(statusCode: acceptableStatusCodes).validate(contentType: contentTypes())
    }
}
