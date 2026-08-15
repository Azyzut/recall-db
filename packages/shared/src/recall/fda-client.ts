// openFDA API Client
// Connects to the FDA's open data API for drug, device, and food recall enforcement data
// Documentation: https://open.fda.gov/apis/
// Free API, no authentication required

export interface FDARecallResult {
  recall_number: string;
  reason_for_recall: string;
  status: string;
  distribution_pattern: string;
  product_description: string;
  product_quantity: string;
  recalling_firm: string;
  city: string;
  state: string;
  classification: 'Class I' | 'Class II' | 'Class III';
  product_type: 'Drug' | 'Device' | 'Food';
  report_date: string;
  recall_initiation_date: string;
  voluntary_mandated: string;
  event_id: string;
  termination_date?: string;
}

export interface FDASearchResponse {
  meta: {
    disclaimer: string;
    terms: string;
    license: string;
    last_updated: string;
    results: {
      skip: number;
      limit: number;
      total: number;
    };
  };
  results: FDARecallResult[];
}

export type FDAProductCategory = 'drug' | 'device' | 'food';

/**
 * Map from product categories used in the app to FDA enforcement endpoints
 */
const CATEGORY_TO_ENDPOINT: Record<string, FDAProductCategory[]> = {
  'Food & Beverages': ['food'],
  'Drugs & Pharmaceuticals': ['drug'],
  'Medical Devices': ['device'],
  'Cosmetics': ['drug'],
};

/**
 * FDA enforcement endpoint URLs by product category
 */
const FDA_ENDPOINTS: Record<FDAProductCategory, string> = {
  drug: 'https://api.fda.gov/drug/enforcement.json',
  device: 'https://api.fda.gov/device/recall.json',
  food: 'https://api.fda.gov/food/enforcement.json',
};

export interface FDASearchOptions {
  productDescription?: string;
  recallingFirm?: string;
  state?: string;
  classification?: 'Class I' | 'Class II' | 'Class III';
  categories?: FDAProductCategory[];
  limit?: number;
  skip?: number;
}

/**
 * openFDA API Client for drug, device, and food recall data
 */
export class FDAClient {
  /**
   * Resolve product category strings to FDA endpoint categories
   */
  resolveCategories(productCategory?: string): FDAProductCategory[] {
    if (!productCategory) {
      return ['drug', 'device', 'food']; // Search all by default
    }

    const mapped = CATEGORY_TO_ENDPOINT[productCategory];
    if (mapped) return mapped;

    // Fallback: search all endpoints
    return ['drug', 'device', 'food'];
  }

  /**
   * Build an openFDA search query string from options
   * openFDA uses a specific query syntax: field:"value"+AND+field:"value"
   */
  private buildSearchQuery(options: FDASearchOptions, broad: boolean = false): string {
    const parts: string[] = [];

    if (options.productDescription && !broad) {
      parts.push(`product_description:"${options.productDescription}"`);
    }
    if (options.recallingFirm) {
      parts.push(`recalling_firm:"${options.recallingFirm}"`);
    }
    if (options.state && !broad) {
      parts.push(`state:"${options.state}"`);
    }
    if (options.classification) {
      parts.push(`classification:"${options.classification}"`);
    }

    // If no specific filters, return a broad search
    if (parts.length === 0) {
      return '';
    }

    return parts.join('+AND+');
  }

  /**
   * Search a single FDA endpoint
   */
  private async searchEndpoint(
    category: FDAProductCategory,
    options: FDASearchOptions
  ): Promise<FDARecallResult[]> {
    const results = await this.fetchEndpoint(category, options);

    // If narrow search returned nothing, retry with broad search (drop product description and state filters)
    if (results.length === 0 && (options.productDescription || options.state)) {
      console.log(`[FDA] Narrow search returned 0 results for ${category}, retrying with broad search...`);
      return this.fetchEndpoint(category, options, true);
    }

    return results;
  }

  private async fetchEndpoint(
    category: FDAProductCategory,
    options: FDASearchOptions,
    broad: boolean = false
  ): Promise<FDARecallResult[]> {
    const baseUrl = FDA_ENDPOINTS[category];
    const searchQuery = this.buildSearchQuery(options, broad);
    const limit = options.limit || 20;
    const skip = options.skip || 0;

    let url = `${baseUrl}?limit=${limit}&skip=${skip}`;
    if (searchQuery) {
      url += `&search=${encodeURIComponent(searchQuery)}`;
    }

    console.log(`[FDA] Searching ${category}${broad ? ' (broad)' : ''}: ${url}`);

    try {
      const response = await fetch(url, {
        signal: AbortSignal.timeout(15000), // 15 second timeout
      });

      if (!response.ok) {
        // openFDA returns 404 when no results are found
        if (response.status === 404) {
          console.log(`[FDA] No results for ${category}${broad ? ' (broad)' : ''}`);
          return [];
        }
        console.warn(`[FDA] ${category} search failed: ${response.status}`);
        return [];
      }

      // Cast required: under the Node lib (this package is server-only)
      // Response.json() resolves to `unknown`, not `any` as it did under the DOM lib.
      const data = (await response.json()) as FDASearchResponse;

      // Tag each result with its product type
      const productTypeMap: Record<FDAProductCategory, FDARecallResult['product_type']> = {
        drug: 'Drug',
        device: 'Device',
        food: 'Food',
      };

      return (data.results || []).map(result => ({
        ...result,
        product_type: result.product_type || productTypeMap[category],
      }));
    } catch (error) {
      console.error(`[FDA] Error searching ${category}:`, error);
      return [];
    }
  }

  /**
   * Search across FDA enforcement endpoints
   * Queries all relevant endpoints (or specific ones based on product category)
   * and merges results
   */
  async search(options: FDASearchOptions = {}): Promise<FDARecallResult[]> {
    const categories = options.categories || ['drug', 'device', 'food'];

    // Query all relevant endpoints in parallel
    const promises = categories.map(category =>
      this.searchEndpoint(category, options)
    );

    const results = await Promise.all(promises);

    // Flatten and deduplicate by recall_number
    const allResults: FDARecallResult[] = [];
    const seen = new Set<string>();

    for (const categoryResults of results) {
      for (const result of categoryResults) {
        const key = result.recall_number || result.event_id;
        if (key && !seen.has(key)) {
          seen.add(key);
          allResults.push(result);
        }
      }
    }

    console.log(`[FDA] Total results across ${categories.length} endpoints: ${allResults.length}`);
    return allResults;
  }

  /**
   * Search by product category string (maps to the correct endpoints)
   */
  async searchByCategory(
    productCategory: string,
    options: Omit<FDASearchOptions, 'categories'> = {}
  ): Promise<FDARecallResult[]> {
    const categories = this.resolveCategories(productCategory);
    return this.search({ ...options, categories });
  }
}

// Export singleton instance
export const fdaClient = new FDAClient();
