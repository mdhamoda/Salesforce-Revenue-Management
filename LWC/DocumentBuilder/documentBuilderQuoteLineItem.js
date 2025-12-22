import { LightningElement, api, wire, track } from 'lwc';
import getQuoteLineItems from '@salesforce/apex/DocumentBuilderQuoteLinesController.getQuoteLineItems';

export default class documentBuilderQuoteLineItem extends LightningElement {
    @api recordId;

    // Boolean flags to show/hide optional columns (from meta.xml)
    @api showProductDescription = false;
    @api showListPrice = false;
    @api showNetTotalPrice = false;
    @api showDiscountPercent = false;
    @api showDiscountAmount = false;
    @api showBundle = false;
    @api showSortOrder = false;

    @track quoteLines = [];

    // Currency formatter for USD (adjust if needed)
    currencyFormatter = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' });

    @wire(getQuoteLineItems, { quoteId: '$recordId' })
    wiredQuoteLines({ error, data }) {
        if (data) {
            this.quoteLines = data.map(q => ({
                Id: q.Id,
                productName: q.Product2.Name,
                productDescription: q.ProductDescription__c,
                productImage: q.Product2.DisplayUrl,
                listPrice: this.formatCurrency(q.ListPrice),
                discountPercent: q.Discount,
                discountAmount: this.formatCurrency(q.DiscountAmount),
                netTotalPrice: this.formatCurrency(q.NetTotalPrice),
                parentProductName: q.ParentQuoteLineItem ? q.ParentQuoteLineItem.Product2.Name : '',
                Quantity: q.Quantity,
                SortOrder: q.SortOrder,
            }));
        } else if (error) {
            console.error('Error fetching Quote Line Items', error);
        }
    }

    formatCurrency(value) {
        return value != null ? this.currencyFormatter.format(value) : '';
    }
}