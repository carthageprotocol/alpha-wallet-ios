//
//  InMemoryTickerIdsFetcher.swift
//  AlphaWallet
//
//  Created by Vladyslav Shepitko on 14.06.2022.
//

import Foundation
import Combine
import CombineExt

/// Provides tokens groups
protocol TokenEntriesProvider {
    func tokenEntries() -> AnyPublisher<[TokenEntry], PromiseError>
}

/// Looks up for tokens groups, and searches for each token matched in group to resolve ticker id. We know that tokens in group relate to same coin, on different chaing.
/// - Loads tokens groups
/// - Finds appropriate group for token
/// - Resolves ticker id, for each token in group
/// - Returns first matching ticker id
class AlphaWalletRemoteTickerIdsFetcher: TickerIdsFetcher {
    private let provider: TokenEntriesProvider
    private let tickerIdsFetcher: CoinGeckoTickerIdsFetcher

    init(provider: TokenEntriesProvider, tickerIdsFetcher: CoinGeckoTickerIdsFetcher) {
        self.provider = provider
        self.tickerIdsFetcher = tickerIdsFetcher
    }

    /// Returns already defined, stored associated with token ticker id
    func tickerId(for token: TokenMappedToTicker) -> AnyPublisher<TickerIdString?, Never> {
        return Just(token)
            .receive(on: Config.backgroundQueue)
            .flatMap { [provider] _ in provider.tokenEntries().replaceError(with: []) }
            .flatMap { [weak self] entries -> AnyPublisher<TickerIdString?, Never> in
                guard let strongSelf = self else { return .empty() }
                return strongSelf.resolveTickerId(in: entries, for: token)
            }.receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }

    private func resolveTickerId(in tokenEntries: [TokenEntry], for token: TokenMappedToTicker) -> AnyPublisher<TickerIdString?, Never> {
        return Just(token)
            .map { token -> TokenEntry? in
                let targetContract: Contract = .init(address: token.contractAddress.eip55String, chainId: token.server.chainID)
                return tokenEntries.first(where: { entry in entry.contracts.contains(targetContract) })
            }.flatMap { [weak self] entry -> AnyPublisher<TickerIdString?, Never> in
                guard let strongSelf = self else { return .empty() }
                guard let entry = entry else { return .just(nil) }

                return strongSelf.lookupAnyTickerId(for: entry, token: token)
            }.eraseToAnyPublisher()
    }
    /// Searches for non nil ticker id in token entries array, might be improved for large entries array.
    private func lookupAnyTickerId(for entry: TokenEntry, token: TokenMappedToTicker) -> AnyPublisher<TickerIdString?, Never> {
        let publishers = entry.contracts.compactMap { contract -> TokenMappedToTicker? in
            guard let contractAddress = AlphaWallet.Address(string: contract.address) else { return nil }
            let server = RPCServer(chainID: contract.chainId)

            return TokenMappedToTicker(symbol: token.symbol, name: token.name, contractAddress: contractAddress, server: server, coinGeckoId: nil)
        }.map { tickerIdsFetcher.tickerId(for: $0) }

        return Publishers.MergeMany(publishers).collect()
            .map { tickerIds in tickerIds.compactMap { $0 }.first }
            .eraseToAnyPublisher()
    }
}

class InMemoryTickerIdsFetcher: TickerIdsFetcher {
    private let storage: TickerIdsStorage

    init(storage: TickerIdsStorage) {
        self.storage = storage
    }

    /// Returns already defined, stored associated with token ticker id
    func tickerId(for token: TokenMappedToTicker) -> AnyPublisher<TickerIdString?, Never> {
        if let id = token.knownCoinGeckoTickerId {
            return .just(id)
        } else {
            let tickerId = storage.knownTickerId(for: token)
            return .just(tickerId)
        }
    }
}

//TODO: Future impl for remote TokenEntries provider
final class RemoteTokenEntriesProvider: TokenEntriesProvider {
    func tokenEntries() -> AnyPublisher<[TokenEntry], PromiseError> {
        return .just([])
            .share()
            .eraseToAnyPublisher()
    }
}

fileprivate let threadSafeForTokenEntries = ThreadSafe(label: "org.alphawallet.swift.tokenEntries")
final class FileTokenEntriesProvider: TokenEntriesProvider {
    private let fileName: String
    private var cachedTokenEntries: [TokenEntry] = []

    init(fileName: String) {
        self.fileName = fileName
    }

    func tokenEntries() -> AnyPublisher<[TokenEntry], PromiseError> {
        if cachedTokenEntries.isEmpty {
            var publisher: AnyPublisher<[TokenEntry], PromiseError>!
            threadSafeForTokenEntries.performSync {
                do {
                    guard let bundlePath = Bundle.main.path(forResource: fileName, ofType: "json") else { throw TokenJsonReader.error.fileDoesNotExist }
                    guard let jsonData = try String(contentsOfFile: bundlePath).data(using: .utf8) else { throw TokenJsonReader.error.fileIsNotUtf8 }
                    do {
                        cachedTokenEntries = try JSONDecoder().decode([TokenEntry].self, from: jsonData)
                        publisher = .just(cachedTokenEntries)
                    } catch DecodingError.dataCorrupted {
                        throw TokenJsonReader.error.fileCannotBeDecoded
                    } catch {
                        throw TokenJsonReader.error.unknown(error)
                    }
                } catch {
                    publisher = .fail(.some(error: error))
                }
            }

            return publisher
        } else {
            return .just(cachedTokenEntries)
        }
    }
}
