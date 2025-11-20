
  
  // ( theres a key point for frontend rem ankit )




module ghostcontext::ghostcontext {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::event;
    use std::string::{Self, String};

    // ========== Error Codes ==========
    const ENotOwner: u64 = 0;
    const ENotListed: u64 = 1;
    const EInsufficientPayment: u64 = 2;
    const EQueryLimitReached: u64 = 3;
    const EInvalidQueryCount: u64 = 4;

    // ========== Structs ==========
    
    /// SHARED OBJECT: Anyone can read/buy, only owner can modify listing
    public struct ContextNFT has key {
        id: UID,
        title: String,
        walrus_blob_id: String,
        owner: address,
        is_listed: bool,
        price_per_query: u64,
        total_revenue: u64,
        total_queries_sold: u64,
        category: String,
    }

    /// OWNED OBJECT: Proof of purchase, only buyer owns it
    public struct QueryReceipt has key, store {
        id: UID,
        context_id: address,
        walrus_blob_id: String,
        queries_purchased: u64,
        queries_remaining: u64,
        purchased_at: u64,
        expires_at: u64,
    }

    /// SHARED REGISTRY: Global marketplace stats
    public struct MarketplaceRegistry has key {
        id: UID,
        total_contexts: u64,
        total_volume: u64,
        total_queries_sold: u64,
    }

    // ========== Events ==========
    
    public struct ContextCreated has copy, drop {
        id: address,
        owner: address,
        title: String,
        walrus_blob_id: String,
    }

    public struct ContextListed has copy, drop {
        context_id: address,
        price_per_query: u64,
    }

    public struct PurchaseEvent has copy, drop {
        buyer: address,
        context_id: address,
        queries_purchased: u64,
        amount_paid: u64,
    }

    public struct QueryConsumed has copy, drop {
        receipt_id: address,
        queries_remaining: u64,
    }

    // ========== Init ==========
    
    fun init(ctx: &mut TxContext) {
        let registry = MarketplaceRegistry {
            id: object::new(ctx),
            total_contexts: 0,
            total_volume: 0,
            total_queries_sold: 0,
        };
        transfer::share_object(registry);
    }

    //  Core Functions

    /// 1. Create and share a new context
    public entry fun create_context(
        title: vector<u8>,
        walrus_blob_id: vector<u8>,
        category: vector<u8>,
        registry: &mut MarketplaceRegistry,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let id = object::new(ctx);
        let context_address = object::uid_to_address(&id);

        let nft = ContextNFT {
            id,
            title: string::utf8(title),
            walrus_blob_id: string::utf8(walrus_blob_id),
            owner: sender,
            is_listed: false,
            price_per_query: 0,
            total_revenue: 0,
            total_queries_sold: 0,
            category: string::utf8(category),
        };

        event::emit(ContextCreated {
            id: context_address,
            owner: sender,
            title: nft.title,
            walrus_blob_id: nft.walrus_blob_id,
        });

        registry.total_contexts = registry.total_contexts + 1;

        // CRITICAL: Share the object so buyers can interact
        transfer::share_object(nft);
    }

    /// 2. List context for sale (Owner only)
    public entry fun list_context(
        nft: &mut ContextNFT,
        price_per_query: u64,
        ctx: &mut TxContext
    ) {
        assert!(nft.owner == tx_context::sender(ctx), ENotOwner);
        assert!(price_per_query > 0, EInvalidQueryCount);
        
        nft.is_listed = true;
        nft.price_per_query = price_per_query;

        event::emit(ContextListed {
            context_id: object::uid_to_address(&nft.id),
            price_per_query,
        });
    }

    /// 3. Unlist from marketplace (Owner only)
    public entry fun unlist_context(
        nft: &mut ContextNFT,
        ctx: &mut TxContext
    ) {
        assert!(nft.owner == tx_context::sender(ctx), ENotOwner);
        nft.is_listed = false;
    }

    /// 4. Update price (Owner only)
    public entry fun update_price(
        nft: &mut ContextNFT,
        new_price: u64,
        ctx: &mut TxContext
    ) {
        assert!(nft.owner == tx_context::sender(ctx), ENotOwner);
        assert!(new_price > 0, EInvalidQueryCount);
        nft.price_per_query = new_price;
    }

    /// 5. Purchase queries (Anyone can call)
    public entry fun purchase_queries(
        nft: &mut ContextNFT,
        queries_to_buy: u64,
        payment: Coin<SUI>,
        registry: &mut MarketplaceRegistry,
        ctx: &mut TxContext
    ) {
        // Validation
        assert!(nft.is_listed, ENotListed);
        assert!(queries_to_buy > 0, EInvalidQueryCount);
        
        let total_cost = nft.price_per_query * queries_to_buy;
        assert!(coin::value(&payment) >= total_cost, EInsufficientPayment);

        // Update NFT stats
        nft.total_revenue = nft.total_revenue + total_cost;
        nft.total_queries_sold = nft.total_queries_sold + queries_to_buy;

        // Update registry
        registry.total_volume = registry.total_volume + total_cost;
        registry.total_queries_sold = registry.total_queries_sold + queries_to_buy;

        // Send payment to owner
        transfer::public_transfer(payment, nft.owner);

        // Mint receipt for buyer
        let buyer = tx_context::sender(ctx);
        let receipt_id = object::new(ctx);
        let receipt = QueryReceipt {
            id: receipt_id,
            context_id: object::uid_to_address(&nft.id),
            walrus_blob_id: nft.walrus_blob_id,
            queries_purchased: queries_to_buy,
            queries_remaining: queries_to_buy,
            purchased_at: tx_context::epoch(ctx),
            expires_at: 0,
        };

        event::emit(PurchaseEvent {
            buyer,
            context_id: object::uid_to_address(&nft.id),
            queries_purchased: queries_to_buy,
            amount_paid: total_cost,
        });

        transfer::public_transfer(receipt, buyer);
    }

    /// 6. Consume a query (Receipt owner only)
    public entry fun consume_query(
        receipt: &mut QueryReceipt,
        _ctx: &mut TxContext
    ) {
        assert!(receipt.queries_remaining > 0, EQueryLimitReached);
        receipt.queries_remaining = receipt.queries_remaining - 1;

        event::emit(QueryConsumed {
            receipt_id: object::uid_to_address(&receipt.id),
            queries_remaining: receipt.queries_remaining,
        });
    }

    /// 7. Batch consume (for when user asks multiple questions)
    public entry fun consume_queries_batch(
        receipt: &mut QueryReceipt,
        count: u64,
        _ctx: &mut TxContext
    ) {
        assert!(receipt.queries_remaining >= count, EQueryLimitReached);
        receipt.queries_remaining = receipt.queries_remaining - count;

        event::emit(QueryConsumed {
            receipt_id: object::uid_to_address(&receipt.id),
            queries_remaining: receipt.queries_remaining,
        });
    }

    // View Functions 

    public fun is_listed(nft: &ContextNFT): bool {
        nft.is_listed
    }

    public fun get_price(nft: &ContextNFT): u64 {
        nft.price_per_query
    }

    public fun get_owner(nft: &ContextNFT): address {
        nft.owner
    }

    public fun get_walrus_blob_id(nft: &ContextNFT): String {
        nft.walrus_blob_id
    }

    public fun get_title(nft: &ContextNFT): String {
        nft.title
    }

    public fun get_revenue(nft: &ContextNFT): u64 {
        nft.total_revenue
    }

    public fun get_queries_remaining(receipt: &QueryReceipt): u64 {
        receipt.queries_remaining
    }

    public fun get_context_from_receipt(receipt: &QueryReceipt): address {
        receipt.context_id
    }

    public fun get_blob_from_receipt(receipt: &QueryReceipt): String {
        receipt.walrus_blob_id
    }

    // ========== Testing ==========
    
    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}