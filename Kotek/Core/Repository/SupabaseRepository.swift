//
//  SupabaseRepository.swift
//  Kotek
//
//  Core repository struct providing raw create, read, update, delete operations
//  against Supabase.
//

import Foundation
import Supabase

nonisolated struct SupabaseRepository {
    let client: SupabaseClient

    init() {
        client = Self.defaultClient()
    }

    init(client: SupabaseClient) {
        self.client = client
    }

    static func defaultClient() -> SupabaseClient {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let urlString = info["SupabaseURL"] as? String,
              let url = URL(string: urlString), url.host() != nil,
              let key = info["SupabasePublishableKey"] as? String,
              !key.isEmpty, !key.hasPrefix("YOUR_")
        else {
            fatalError(
                "Supabase is not configured: set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY in Config.xcconfig (see Config.xcconfig.template)."
            )
        }
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        )
    }

    // MARK: - Auth

    func userID() async throws -> UUID {
        if client.auth.currentSession != nil {
            return try await client.auth.session.user.id
        }
        return try await client.auth.signInAnonymously().user.id
    }

    // MARK: - Create

    func create(_ value: some Encodable & Sendable, in table: String) async throws {
        try await client.from(table).insert(value).execute()
    }

    func create(_ values: [some Encodable & Sendable], in table: String) async throws {
        guard !values.isEmpty else { return }
        try await client.from(table).insert(values).execute()
    }

    // MARK: - Read

    func read<T: Decodable & Sendable>(from table: String) async throws -> [T] {
        try await client.from(table).select().execute().value
    }

    func read<T: Decodable & Sendable>(
        from table: String,
        matching column: String,
        in values: [some PostgrestFilterValue]
    ) async throws -> [T] {
        guard !values.isEmpty else { return [] }
        let filterValues: [any PostgrestFilterValue] = values.map { $0 as any PostgrestFilterValue }
        return try await client.from(table).select().in(column, values: filterValues).execute().value
    }

    func read<T: Decodable & Sendable>(
        from table: String,
        matching column: String,
        equals value: some PostgrestFilterValue
    ) async throws -> [T] {
        try await client.from(table).select().eq(column, value: value).execute().value
    }

    // MARK: - Update

    func update(
        _ value: some Encodable & Sendable,
        in table: String,
        matching column: String,
        equals filterValue: some PostgrestFilterValue
    ) async throws {
        try await client.from(table).update(value).eq(column, value: filterValue).execute()
    }

    // MARK: - Delete

    func delete(
        from table: String,
        matching column: String,
        equals value: some PostgrestFilterValue
    ) async throws {
        try await client.from(table).delete().eq(column, value: value).execute()
    }

    func delete(
        from table: String,
        matching column1: String,
        equals value1: some PostgrestFilterValue,
        andColumn column2: String,
        gte value2: some PostgrestFilterValue
    ) async throws {
        try await client.from(table)
            .delete()
            .eq(column1, value: value1)
            .gte(column2, value: value2)
            .execute()
    }

    // MARK: - Upsert

    func upsert(_ value: some Encodable & Sendable, in table: String) async throws {
        try await client.from(table).upsert(value).execute()
    }

    func upsert(_ values: [some Encodable & Sendable], in table: String) async throws {
        guard !values.isEmpty else { return }
        try await client.from(table).upsert(values).execute()
    }
}
