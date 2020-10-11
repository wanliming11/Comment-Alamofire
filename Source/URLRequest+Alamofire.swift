//
//  URLRequest+Alamofire.swift
//
//  Copyright (c) 2019 Alamofire Software Foundation (http://alamofire.org/)
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

import Foundation

// MAKR： Comment start

public extension URLRequest {
    /// Returns the `httpMethod` as Alamofire's `HTTPMethod` type.
    /// 把 URLRequest 的方法转换为 Alamofire 的 HttpMethod
    var method: HTTPMethod? {
        get { httpMethod.flatMap(HTTPMethod.init) }
        set { httpMethod = newValue?.rawValue }
    }

    func validate() throws {
        /// url 如果是 fileURL的话，抛出错误
        if let url = url, url.isFileURL {
            // This should become another urlRequestValidationFailed error in Alamofire 6.
            throw AFError.invalidURL(url: url)
        }

        /// 方法是 get，但是却包含了 bodyData 也会包含错误
        if method == .get, let bodyData = httpBody {
            throw AFError.urlRequestValidationFailed(reason: .bodyDataInGETRequest(bodyData))
        }
    }
}

// MAKR： Comment end
