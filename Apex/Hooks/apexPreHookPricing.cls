public class apexPreHookPricing implements RevSignaling.SignalingApexProcessor {

    public RevSignaling.TransactionResponse execute(RevSignaling.TransactionRequest request) {
        System.debug('Executing PREHOOK');
        //cuurency callout enable if real time currency is needed
        //HookService_CurrencyRateService.getRates(baseCurrency, IsoCodeCsv)
        try {
            //HookService_CurrencyRateService.getRates(null, null);
        } catch (Exception ex) {
            System.debug(' Exception during callout: ' + ex.getMessage());
        }
        //
        try{
        String contextId = request.ctxInstanceId;
        Context.IndustriesContext industriesContext = new Context.IndustriesContext();
        Map<String,Object> salesTransactionQueryInput = new Map<String,Object>{
            'contextId' => contextId,
            'tags'      => new List<String>{ 'SalesTransactionItem', 'SalesTransaction','SalesTransactionItemAttribute' }
        };
        Map<String,Object> salesTransactionQueryOutput = industriesContext.queryTags(salesTransactionQueryInput);
        Map<String,Object> salesTransactionResult = 
            (Map<String,Object>) salesTransactionQueryOutput.get('queryResult');
        
        List<Object> salesTransactionItemNodes =
            (List<Object>) salesTransactionResult.get('SalesTransactionItem');
        List<Object> salesTransactionNodes =
            (List<Object>) salesTransactionResult.get('SalesTransaction');
        // system.debug('contextId'+ contextId);
        // system.debug('salesTransactionItemNodes.size '+ salesTransactionItemNodes.size());
        // system.debug('salesTransactionNodes.size '+ salesTransactionNodes.size());
        for(Object eachsalesTransaction: salesTransactionNodes){
            // system.debug('salesTransactionNodes '+ eachsalesTransaction);
        }
        List<Map<String, Object>> itemNodeUpdates = new List<Map<String, Object>>();
        for(Object eachSalesTransactionItem: salesTransactionItemNodes){
            // system.debug('eachSalesTransactionItem '+ eachSalesTransactionItem);
            Map<String, Object> itemNode = (Map<String, Object>) eachSalesTransactionItem;
            List<Object> dataPath = (List<Object>) itemNode.get('dataPath');
            Map<String, Object> eachSalesTransactionItemtagMap = (Map<String, Object>) itemNode.get('tagValue');
            Decimal newUnitprice;
            Decimal CustomUnitPrice;
            Decimal NetUnitPrice;
             if (dataPath[2] != null) {
                 // System.debug('Full item itemNode: ' + JSON.serialize(itemNode));
                 // System.debug('Full item dataPath: ' + JSON.serialize(dataPath));
                 // System.debug('Full item tagValue: ' + JSON.serialize(itemNode.get('tagValue')));
                 // System.debug('dataPath ' + dataPath[0]);
                 // System.debug('dataPath Quote Id ' + dataPath[1]);
                 // System.debug('dataPath LineItem Id ' + dataPath[2]);
                 // System.debug('UnitPrice ' + (Decimal)((Map<String, Object>) eachSalesTransactionItemtagMap.get('CustomUnitPrice__c')).get('tagValue'));
                 Boolean DeletedItem = false;
                 NetUnitPrice =  (Decimal)((Map<String, Object>) eachSalesTransactionItemtagMap.get('NetUnitPrice')).get('tagValue');
                 if((Decimal)((Map<String, Object>) eachSalesTransactionItemtagMap.get('CustomUnitPrice__c')).get('tagValue')!=null) {
                     CustomUnitPrice =  (Decimal)((Map<String, Object>) eachSalesTransactionItemtagMap.get('CustomUnitPrice__c')).get('tagValue');
                 }
                 //perform a callout to get the real time externalpricing and update CustomUnitPrice - to be done
                 //newUnitprice =  NetUnitPrice < 100 ? 100 : NetUnitPrice;
                 newUnitprice =  CustomUnitPrice != null ? CustomUnitPrice : null;
                 dataPath.remove(0);
                 itemNodeUpdates.add(new Map<String, Object>{
                'nodePath' => new Map<String, Object>{ 'dataPath' => dataPath },
                'attributes' => new List<Object>{
                    new Map<String, Object>{
                        'attributeName' => 'CustomUnitPrice__c',
                        'attributeValue' => newUnitprice
                   		}
                	}
            		});
                }
        }
        if (!itemNodeUpdates.isEmpty()) {
            Map<String, Object> updateInput = new Map<String, Object>{
                'contextId' => contextId,
                'nodePathAndAttributes' => itemNodeUpdates
            };
            System.debug('--- PREHOOK: SUBMITTING CONTEXT UPDATE ---');
            // System.debug(JSON.serializePretty(updateInput));
                industriesContext.updateContextAttributes(updateInput);
        	}
        } catch (Exception ex) {
            System.debug(' Exception during PreHook update: ' + ex.getMessage());
            RevSignaling.TransactionResponse response = new RevSignaling.TransactionResponse();
            if(ex.getMessage().contains('data not in updatable state')){
        	response.status = RevSignaling.TransactionStatus.SUCCESS;
        	response.message = 'Apex executed successfully ';
                                        } else{
                                            response.status = RevSignaling.TransactionStatus.FAILED;
                                            response.message = ' Exception during PreHook update: ' + ex.getMessage();
                                        }
        	return response;
        }
        RevSignaling.TransactionResponse response = new RevSignaling.TransactionResponse();
        response.status = RevSignaling.TransactionStatus.SUCCESS;
        response.message = 'Apex prehook executed successfully: ';
        return response;

    }
}
