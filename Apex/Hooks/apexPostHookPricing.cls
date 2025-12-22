public class apexPostHookPricing implements RevSignaling.SignalingApexProcessor {

    public RevSignaling.TransactionResponse execute(RevSignaling.TransactionRequest request) {
        RevSignaling.TransactionResponse response = new RevSignaling.TransactionResponse();

        try {
            String contextId = request.ctxInstanceId;
            Context.IndustriesContext industriesContext = new Context.IndustriesContext();

            // Use metadata types to control these Options
            // =========================
            // ProductDescription Options (defined at the start)
            // =========================
            Boolean resetDescription = true;      // Option 1: reset to empty string
            Boolean includeJson = false;           // Option 2: include JSON of attributes
            Boolean includeAttributes = true;      // Option 3: include flattened attributes
            Boolean includeParentName = false;     // Option 4: prepend parent product name
            // =========================
            // SortOrder Options (defined at the start)
            // =========================
            Boolean includeSortOrder = true;     // Option 5: calculate and update sortorder

            // =========================
            // Query context nodes
            // =========================
            Map<String,Object> salesTransactionQueryInput = new Map<String,Object>{
                'contextId' => contextId,
                'tags' => new List<String>{ 'SalesTransactionItem', 'SalesTransaction', 'SalesTransactionItemAttribute' }
            };

            Map<String,Object> salesTransactionQueryOutput = industriesContext.queryTags(salesTransactionQueryInput);
            Map<String,Object> salesTransactionResult = (Map<String,Object>) salesTransactionQueryOutput.get('queryResult');

            List<Object> salesTransactionItemNodes = (List<Object>) salesTransactionResult.get('SalesTransactionItem');
            List<Object> salesTransactionItemAttrNodes = (List<Object>) salesTransactionResult.get('SalesTransactionItemAttribute');

            // =========================
            // Prepare attribute maps only if needed
            // =========================
            Map<String,String> parentCtxIdToAttrMapPlainTxt = new Map<String,String>();
            Map<String,String> parentCtxIdToAttrMapJson = new Map<String,String>();

            if (includeAttributes) {
                parentCtxIdToAttrMapPlainTxt = buildFlattenedAttributesMap(salesTransactionItemAttrNodes);
            }

            if (includeJson) {
                parentCtxIdToAttrMapJson = buildJsonAttributesMap(salesTransactionItemAttrNodes);
            }

            // =========================
            // Build mappings: ProductName and ParentId
            // =========================
            Map<String,String> itemCtxIdToProductName = buildItemCtxIdToProductName(salesTransactionItemNodes);
            Map<String,String> itemCtxIdToParent = buildItemCtxIdToParent(salesTransactionItemNodes);

            // =========================
            // Recalculate hierarchical sort
            // =========================
            Map<String,Integer> sortMap;
                if(includeSortOrder) sortMap = calculateHierarchicalSortOrder(salesTransactionItemNodes);

            // =========================
            // Prepare updates
            // =========================
            List<Map<String,Object>> itemNodeUpdates = new List<Map<String,Object>>();
            for (Object itemObj : salesTransactionItemNodes) {
                Map<String,Object> itemNode = (Map<String,Object>) itemObj;
                List<Object> dataPath = (List<Object>) itemNode.get('dataPath');
                String itemCtxId = String.valueOf(dataPath[dataPath.size()-1]);
                List<Object> nodePath = new List<Object>(dataPath);
                nodePath.remove(0); // remove root context
                List<Object> attributes = new List<Object>();

                // =========================
                // Build ProductDescription dynamically based on options
                // =========================
                String description = '';

                // Option 1: Reset to empty string
                if (resetDescription) {
                    description = '';
                }

                // Option 2: Include JSON of attributes
                if (includeJson && parentCtxIdToAttrMapJson.containsKey(itemCtxId)) {
                    description += parentCtxIdToAttrMapJson.get(itemCtxId);
                }

                // Option 3: Include flattened attributes
                if (includeAttributes && parentCtxIdToAttrMapPlainTxt.containsKey(itemCtxId)) {
                    if (!String.isBlank(description)) description += '\n';
                    description += parentCtxIdToAttrMapPlainTxt.get(itemCtxId);
                }

                // Option 4: Include parent product name
                if (includeParentName && itemCtxIdToParent.containsKey(itemCtxId)) {
                    String parentId = itemCtxIdToParent.get(itemCtxId);
                    if (!String.isBlank(parentId) && itemCtxIdToProductName.containsKey(parentId)) {
                        description = '(' + itemCtxIdToProductName.get(parentId) + ') \n' + description;
                    }
                }

                // =========================
                // Assign to ProductDescription__c
                // =========================
                if(resetDescription){
                    attributes.add(new Map<String,Object>{
                        'attributeName' => 'ProductDescription__c',
                            'attributeValue' =>  description
                            });
                    }
                // =========================
                // Assign SortOrder
                // =========================
                if (includeSortOrder && sortMap.containsKey(itemCtxId)) {
                    attributes.add(new Map<String,Object>{
                        'attributeName' => 'ItemSortOrder',
                        'attributeValue' => sortMap.get(itemCtxId)
                    });
                }

                if (!attributes.isEmpty()) {
                    itemNodeUpdates.add(new Map<String,Object>{
                        'nodePath' => new Map<String,Object>{ 'dataPath' => nodePath },
                        'attributes' => attributes
                    });
                }
            }

            // =========================
            // Update context attributes
            // =========================
            if (!itemNodeUpdates.isEmpty()) {
                industriesContext.updateContextAttributes(
                    new Map<String,Object>{
                        'contextId' => contextId,
                        'nodePathAndAttributes' => itemNodeUpdates
                    }
                );
            }

            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'Apex Post Hook executed successfully';

        } catch (Exception ex) {
            response.status = ex.getMessage().contains('data not in updatable state') ?
                RevSignaling.TransactionStatus.SUCCESS : RevSignaling.TransactionStatus.FAILED;
            response.message = ex.getMessage().contains('data not in updatable state') ?
                'Apex Post Hook executed successfully' : 'Exception: Post Hook failed ' + ex.getMessage();
            return response;
        }

        return response;
    }

    // =========================
    // Flatten Attributes Helper
    // =========================
    private static Map<String,String> buildFlattenedAttributesMap(List<Object> salesTransactionItemAttrNodes) {
        Map<String, Map<String,String>> parentCtxIdToAttrMap = new Map<String, Map<String,String>>();
        for (Object attrObj : salesTransactionItemAttrNodes) {
            Map<String,Object> attrNode = (Map<String,Object>) attrObj;
            Map<String,Object> tagMap = (Map<String,Object>) attrNode.get('tagValue');

            String attributeName = (tagMap.containsKey('Attribute') && tagMap.get('Attribute') != null) ?
                String.valueOf(((Map<String,Object>)tagMap.get('Attribute')).get('tagValue')) : null;
            String attributeValue = (tagMap.containsKey('AttributeValue') && tagMap.get('AttributeValue') != null) ?
                String.valueOf(((Map<String,Object>)tagMap.get('AttributeValue')).get('tagValue')) : null;
            String parentCtxId = (tagMap.containsKey('SalesTransactionItemAttrParent') && tagMap.get('SalesTransactionItemAttrParent') != null) ?
                String.valueOf(((Map<String,Object>)tagMap.get('SalesTransactionItemAttrParent')).get('tagValue')) : null;

            if (!String.isBlank(parentCtxId)) {
                if (!parentCtxIdToAttrMap.containsKey(parentCtxId)) parentCtxIdToAttrMap.put(parentCtxId, new Map<String,String>());
                parentCtxIdToAttrMap.get(parentCtxId).put(attributeName, attributeValue);
            }
        }

        return flattenAndSort(parentCtxIdToAttrMap);
    }

    // =========================
    // JSON Attributes Helper
    // =========================
    private static Map<String,String> buildJsonAttributesMap(List<Object> salesTransactionItemAttrNodes) {
        Map<String, Map<String,String>> parentCtxIdToAttrMap = new Map<String, Map<String,String>>();
        for (Object attrObj : salesTransactionItemAttrNodes) {
            Map<String,Object> attrNode = (Map<String,Object>) attrObj;
            Map<String,Object> tagMap = (Map<String,Object>) attrNode.get('tagValue');

            String attributeName = (tagMap.containsKey('Attribute') && tagMap.get('Attribute') != null) ?
                String.valueOf(((Map<String,Object>)tagMap.get('Attribute')).get('tagValue')) : null;
            String attributeValue = (tagMap.containsKey('AttributeValue') && tagMap.get('AttributeValue') != null) ?
                String.valueOf(((Map<String,Object>)tagMap.get('AttributeValue')).get('tagValue')) : null;
            String parentCtxId = (tagMap.containsKey('SalesTransactionItemAttrParent') && tagMap.get('SalesTransactionItemAttrParent') != null) ?
                String.valueOf(((Map<String,Object>)tagMap.get('SalesTransactionItemAttrParent')).get('tagValue')) : null;

            if (!String.isBlank(parentCtxId)) {
                if (!parentCtxIdToAttrMap.containsKey(parentCtxId)) parentCtxIdToAttrMap.put(parentCtxId, new Map<String,String>());
                parentCtxIdToAttrMap.get(parentCtxId).put(attributeName, attributeValue);
            }
        }

        Map<String,String> result = new Map<String,String>();
        for (String parentCtxId : parentCtxIdToAttrMap.keySet()) {
            result.put(parentCtxId, JSON.serialize(parentCtxIdToAttrMap.get(parentCtxId)));
        }
        return result;
    }

    // =========================
    // Map of itemCtxId → ProductName
    // =========================
    private static Map<String,String> buildItemCtxIdToProductName(List<Object> salesTransactionItemNodes) {
        Map<String,String> itemCtxIdToProductName = new Map<String,String>();
        for (Object itemObj : salesTransactionItemNodes) {
            Map<String,Object> itemNode = (Map<String,Object>) itemObj;
            List<Object> dataPath = (List<Object>) itemNode.get('dataPath');
            Map<String,Object> tagMap = (Map<String,Object>) itemNode.get('tagValue');

            String itemCtxId = String.valueOf(dataPath[dataPath.size()-1]);
            String productName = '';
            if (tagMap.containsKey('ProductName') && tagMap.get('ProductName') != null) {
                productName = String.valueOf(((Map<String,Object>)tagMap.get('ProductName')).get('tagValue'));
            }
            itemCtxIdToProductName.put(itemCtxId, productName);
        }
        return itemCtxIdToProductName;
    }

    // =========================
    // Map of itemCtxId → ParentId
    // =========================
    private static Map<String,String> buildItemCtxIdToParent(List<Object> salesTransactionItemNodes) {
        Map<String,String> itemCtxIdToParent = new Map<String,String>();
        for (Object itemObj : salesTransactionItemNodes) {
            Map<String,Object> itemNode = (Map<String,Object>) itemObj;
            List<Object> dataPath = (List<Object>) itemNode.get('dataPath');
            Map<String,Object> tagMap = (Map<String,Object>) itemNode.get('tagValue');

            String itemCtxId = String.valueOf(dataPath[dataPath.size()-1]);
            String parentCtxId = null;
            if (tagMap.containsKey('ParentSalesTransactionItem') && tagMap.get('ParentSalesTransactionItem') != null) {
                parentCtxId = String.valueOf(((Map<String,Object>)tagMap.get('ParentSalesTransactionItem')).get('tagValue'));
            }
            itemCtxIdToParent.put(itemCtxId, parentCtxId);
        }
        return itemCtxIdToParent;
    }

    // =========================
    // Flatten Map Helper
    // =========================
    public static Map<String,String> flattenAndSort(Map<String, Map<String,String>> parentCtxIdToAttrMap) {
        Map<String,String> result = new Map<String,String>();
        for (String parentCtxId : parentCtxIdToAttrMap.keySet()) {
            Map<String,String> attrMap = parentCtxIdToAttrMap.get(parentCtxId);
            List<String> keys = new List<String>(attrMap.keySet());
            keys.sort();
            List<String> lines = new List<String>();
            for (String k : keys) {
                lines.add(k + ' : ' + attrMap.get(k));
            }
            result.put(parentCtxId, String.join(lines, '\n'));
        }
        return result;
    }

    // =========================
    // Hierarchical Sort
    // =========================
    public static Map<String,Integer> calculateHierarchicalSortOrder(List<Object> salesTransactionItemNodes) {
        Map<String,String> itemToName = new Map<String,String>();
        Map<String,String> itemToParent = new Map<String,String>();
        Map<String,List<String>> childrenByParent = new Map<String,List<String>>();

        for (Object itemObj : salesTransactionItemNodes) {
            Map<String,Object> itemNode = (Map<String,Object>) itemObj;
            List<Object> dataPath = (List<Object>) itemNode.get('dataPath');
            Map<String,Object> tagMap = (Map<String,Object>) itemNode.get('tagValue');

            String itemCtxId = String.valueOf(dataPath[dataPath.size()-1]);
            String parentCtxId = null;
            if (tagMap.containsKey('ParentSalesTransactionItem') && tagMap.get('ParentSalesTransactionItem') != null) {
                parentCtxId = String.valueOf(((Map<String,Object>)tagMap.get('ParentSalesTransactionItem')).get('tagValue'));
            }

            String productName = '';
            if (tagMap.containsKey('ProductName') && tagMap.get('ProductName') != null) {
                productName = String.valueOf(((Map<String,Object>)tagMap.get('ProductName')).get('tagValue'));
            }

            itemToName.put(itemCtxId, productName);
            itemToParent.put(itemCtxId, parentCtxId);

            if (!String.isBlank(parentCtxId)) {
                if (!childrenByParent.containsKey(parentCtxId)) childrenByParent.put(parentCtxId, new List<String>());
                childrenByParent.get(parentCtxId).add(itemCtxId);
            }
        }

        List<String> topParents = new List<String>();
        for (String itemCtxId : itemToName.keySet()) {
            if (String.isBlank(itemToParent.get(itemCtxId))) topParents.add(itemCtxId);
        }
        topParents.sort(new CtxIdByNameComparator(itemToName));

        Map<String,Integer> result = new Map<String,Integer>();
        Integer counter = 1;
        for (String parent : topParents) {
            counter = assignSortOrderRecursive(parent, childrenByParent, itemToName, result, counter);
        }

        return result;
    }

    private static Integer assignSortOrderRecursive(
        String parent, Map<String,List<String>> childrenByParent,
        Map<String,String> itemToName, Map<String,Integer> result, Integer counter
    ) {
        result.put(parent, counter++);
        if (childrenByParent.containsKey(parent)) {
            List<String> children = childrenByParent.get(parent);
            children.sort(new CtxIdByNameComparator(itemToName));
            for (String child : children) {
                counter = assignSortOrderRecursive(child, childrenByParent, itemToName, result, counter);
            }
        }
        return counter;
    }

    private class CtxIdByNameComparator implements Comparator<String> {
        private Map<String,String> ctxIdToName;
        public CtxIdByNameComparator(Map<String,String> ctxIdToName) { this.ctxIdToName = ctxIdToName; }
        public Integer compare(String a, String b) {
            String nA = ctxIdToName.get(a); if (nA==null) nA='';
            String nB = ctxIdToName.get(b); if (nB==null) nB='';
            return nA.toLowerCase().compareTo(nB.toLowerCase());
        }
    }
}