//
//  NewsAPI.swift
//  XCANews
//
//  Created by Alfian Losari on 6/27/21.
//

import Foundation

struct NewsAPI {
    
    static let shared = NewsAPI()
    private init() {}
    
    private let apiKey = "5d34bf2378614a46934bf52ab5075ac9"
    private let session = URLSession.shared
    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    
    func fetch(from category: Category) async throws -> [Article] {
        try await fetchArticles(from: generateNewsURL(from: category))
    }
    
    func search(for query: String) async throws -> [Article] {
        try await fetchArticles(from: generateSearchURL(from: query))
    }
    
    func fetchAllCategoryArticles() async throws -> [CategoryArticles] {
        try await withThrowingTaskGroup(of: Result<CategoryArticles, Error>.self) { group in
            for category in Category.allCases {
                group.addTask { await fetchResult(from: category) }
            }
            
            var results = [Result<CategoryArticles, Error>]()
            for try await result in group {
                results.append(result)
            }
            
            if let first = results.first,
               case .failure(let error) = first,
               (error as NSError).code == 401 {
                throw error
            }
            
            var categories = [CategoryArticles]()
            for result in results {
                if case .success(let value) = result {
                    categories.append(value)
                }
            }
            
            categories.sort { $0.category.sortIndex < $1.category.sortIndex }
            return categories
        }
    }
    
    private func fetchResult(from category: Category) async -> Result<CategoryArticles, Error> {
        do {
            let articles = try await fetchArticles(from: generateNewsURL(from: category))
            return .success(CategoryArticles(category: category, articles: articles))
        } catch {
            return .failure(error)
        }
    }
    
    private func fetchArticles(from url: URL) async throws -> [Article] {
        let (data, response) = try await session.data(from: url)
        
        guard let response = response as? HTTPURLResponse else {
            throw generateError(description: "Bad Response")
        }
        
        switch response.statusCode {
            
        case (200...299), (400...499):
            let apiResponse = try jsonDecoder.decode(NewsAPIResponse.self, from: data)
            if apiResponse.status == "ok" {
                return apiResponse.articles ?? []
            } else {
                let errorCode = response.statusCode == 401 ? 401 : 1
                throw generateError(code: errorCode, description: apiResponse.message ?? "An error occured")
            }
        default:
            throw generateError(description: "A server error occured")
        }
    }
    
    private func generateError(code: Int = 1, description: String) -> Error {
        NSError(domain: "NewsAPI", code: code, userInfo: [NSLocalizedDescriptionKey: description])
    }
    
    private func generateSearchURL(from query: String) -> URL {
        let percentEncodedString = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        var url = "https://newsapi.org/v2/everything?"
        url += "apiKey=\(apiKey)"
        url += "&language=en"
        url += "&q=\(percentEncodedString)"
        return URL(string: url)!
    }
    
    private func generateNewsURL(from category: Category) -> URL {
        var url = "https://newsapi.org/v2/top-headlines?"
        url += "apiKey=\(apiKey)"
        url += "&language=en"
        url += "&category=\(category.rawValue)"
        return URL(string: url)!
    }
}
