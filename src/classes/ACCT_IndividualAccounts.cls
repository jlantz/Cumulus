/*
    Copyright (c) 2009, Salesforce.com Foundation
    All rights reserved.
    
    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:
    
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of the Salesforce.com Foundation nor the names of
      its contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.
 
    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT 
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS 
    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE 
    COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, 
    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; 
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER 
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT 
    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN 
    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
    POSSIBILITY OF SUCH DAMAGE.
*/
/**
* @author Salesforce.com Foundation
* @date 2011 (1.x)
* @description Implements one of three account models, 1x1 or bucket or HH - controls syncing within the model 
*/
public with sharing class ACCT_IndividualAccounts {
    
    /// <name> IndividualAccounts </name>
    /// <summary> Default Constructor </summary>
    public ACCT_IndividualAccounts() {}

    private static npe01__Contacts_and_Orgs_Settings__c ContactsSettings;
    
    private static Set<String> EasternOrderLanguages = new Set<String>{
        'ja','ko','vi','hu','ro','zh_CN','zh_TW'
    };
              
    private static String OrgLanguage { get {
        if (OrgLanguage == null)
            OrgLanguage = UserInfo.getLocale();// [Select LanguageLocaleKey From Organization].LanguageLocaleKey;
        return OrgLanguage;             
    } set; }       
    
    /// <name> IndividualAccounts </name>
    /// <summary> Overloads the IndividualAccounts object constructor to handle Contact processing </summary>
    /// <param name="contacts"> Contact objects that are being triggered </param>
    /// <param name="oldContacts"> Contact object values before trigger event </param>
    /// <param name="ta"> Trigger action that is occuring </param>
    public ACCT_IndividualAccounts(Contact[] contacts, Contact[] oldContacts, CAO_Constants.triggerAction ta) {
        ContactsSettings = CAO_Constants.getContactsSettings();
            
        if (!ContactsSettings.npe01__Disable_Account_Model_Trigger__c) {
            List<Contact> listContactNeedAccount = new List<Contact>();
            List<Contact> listContactNeedAccountUpdate = new List<Contact>();
            List<Contact> listContactAccountDelete = new List<Contact>();
            List<Contact> listContactNeedBucketAccount = new List<Contact>();
            Map<Id,Id> mapAccountIdContactId = new Map<Id,Id>();
            list<Id> listAccountIdHHToUpdate = new list<Id>();
            list<Id> listAccountIdHHToRename = new list<Id>();
            Map<Id,Account> mapContactIdAccount = null;
            
            
            if (ta == CAO_Constants.triggerAction.beforeInsert || ta == CAO_Constants.triggerAction.beforeUpdate) {                    
                // need to query account fields we need to look at
                Set<Id> setAccountId = new Set<Id>();
                for (Contact c : contacts) 
                    setAccountId.add(c.AccountId);
                mapContactIdAccount = new Map<Id,Account>([select Id, npe01__One2OneContact__c, npe01__SYSTEM_AccountType__c from Account where Id IN :setAccountId]);
            } else if (ta == CAO_Constants.triggerAction.AfterInsert || ta == CAO_Constants.triggerAction.AfterUpdate) {
	           // requery to get correct Account values (and all the other fields we will look at)
	           contacts = [select id,npe01__SystemAccountProcessor__c,npe01__Private__c,AccountId,Account.npe01__SYSTEMIsIndividual__c,
	                Account.npe01__SYSTEM_AccountType__c,Account.npe01__One2OneContact__c,npe01__Organization_Type__c,Account.Name,firstname, lastname,
	                Salutation, npo02__Naming_Exclusions__c,
	                MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry, OtherStreet, OtherCity, OtherState, OtherPostalCode, OtherCountry, 
	                Phone, Fax from Contact where Id IN :contacts];
            }        
                        
            // AFTER DELETE
            if (ta == CAO_Constants.triggerAction.afterDelete) {
            	for (Contact c : oldContacts)
                    listContactAccountDelete.add(c);                     
            } else {               
                Integer i = 0; // used to index into oldContacts when needed                	
                for (Contact c : contacts) {
                    
                    // BEFORE INSERT
                    if (ta == CAO_Constants.triggerAction.beforeInsert) {
                        /* HH Account should be created if:
                            1. The account isn't set by the user
                            2. The npe01__Private__c checkbox isn't set by the user
                            3. The HH Account model is chosen in the npe01__SystemAccountProcessor__c
                        */
                        if (CAO_Constants.isHHAccountModel() && c.AccountId == null && c.npe01__Private__c != true) {
                            listContactNeedAccount.add(c);
                        } 
                                             
                        /*one-to-one account should be created if:
                            1. The account isn't set by the user
                            2. The npe01__Private__c checkbox isn't set by the user
                            3. The one-to-one model is chosen in the npe01__SystemAccountProcessor__c
                        */ 
                        else if (CAO_Constants.isOneToOne() && c.npe01__Private__c != true && 
                            (c.AccountId == null || mapContactIdAccount.get(c.AccountId).npe01__SYSTEM_AccountType__c == CAO_Constants.ONE_TO_ONE_ORGANIZATION_TYPE) ) {
                            
                            // Avoid creating a new contact with the 1:1 account of another contact  
                            if (c.AccountId != null)
                                c.AccountId = null;
                           
                            listContactNeedAccount.add(c);
                        }                    
                        /*contact should be connected to the bucket account if:
                            1. The account isn't set by the user
                            2. The npe01__Private__c checkbox isn't set by the user
                            3. The Individual model is chosen in the npe01__SystemAccountProcessor__c
                        */
                        else if (CAO_Constants.isBucketModel() && c.AccountId == null && c.npe01__Private__c != true) {        
                            listContactNeedBucketAccount.add(c);
                        }                                                
                    }
        
                    // AFTER INSERT
                    if (ta == CAO_Constants.triggerAction.afterInsert) {
                        /*grab the Accounts that need to have the newly assigned Contact Id to them if:
                            1. If the contact is connected to an Account
                            2. The Contact is flagged as an individual
                            3. The one-to-one or HH Account model is chosen in the npe01__SystemAccountProcessor__c
                        */
                        if (c.AccountId != null && c.npe01__Private__c != true && !CAO_Constants.isBucketModel() && c.Account.npe01__SYSTEMIsIndividual__c) {
                            // contacts are connected to Accounts, make the connection in the other direction
                            mapAccountIdContactId.put(c.AccountId, c.Id);
                        }
                        // there is no after insert processing for the bucket account model.

                        // HHAccount renaming needs to be called to set various HH naming fields like greeting.
                        if (c.AccountId != null && c.Account.npe01__SYSTEM_AccountType__c == CAO_Constants.HH_ACCOUNT_TYPE)
                           listAccountIdHHToRename.add(c.AccountId);    
                    }
        
                    // BEFORE UPDATE
                    if (ta == CAO_Constants.triggerAction.beforeUpdate) {
                        /* HH account should be created if:
                            1. The account has been blanked out by the user
                            2. The npe01__Private__c checkbox isn't set by the user
                            3. The HH Account model is chosen in the npe01__SystemAccountProcessor__c
                        */
                        if (CAO_Constants.isHHAccountModel() && c.AccountId == null && c.npe01__Private__c != true) {
                            listContactNeedAccount.add(c);
                        }          
                        /*one-to-one account should be created if:
                            1. The account has been blanked out by the user
                            2. The npe01__Private__c checkbox isn't set by the user
                            3. The one-to-one model is chosen in the npe01__SystemAccountProcessor__c
                        */
                        else if (CAO_Constants.isOneToOne() && c.npe01__Private__c != true && 
                            (c.AccountId == null || mapContactIdAccount.get(c.AccountId).npe01__SYSTEM_AccountType__c == CAO_Constants.ONE_TO_ONE_ORGANIZATION_TYPE) ) {
                            
                            // Avoid creating a new contact with the 1:1 account of another contact  
                            if (c.AccountId != null && mapContactIdAccount.get(c.AccountId).npe01__One2OneContact__c != c.Id)
                                c.AccountId = null;

                            listContactNeedAccount.add(c);
                        }          
                        /*contact should be connected to the bucket account if:
                            1. The account has been blanked out by the user
                            2. The npe01__Private__c checkbox isn't set by the user
                            3. The Individual model is chosen in the npe01__SystemAccountProcessor__c
                        */ 
                        else if (CAO_Constants.isBucketModel() && c.AccountId == null && c.npe01__Private__c != true) {        
                            listContactNeedBucketAccount.add(c);
                        }
                        // for contacts marked private after they have been created, break the relationship from their account (any model)
                        if (c.AccountId != null && c.npe01__Private__c == true) {
                            c.AccountId = null;
                        } 
                    }
        
                    // AFTER UPDATE
                    if (ta == CAO_Constants.triggerAction.afterUpdate) {
                        /*if the contact is in the one-to-one model, changes to fields on the Contact
                        will require data changes on the Account to keep some fields in sync
                        */
                        if (c.npe01__Organization_Type__c == CAO_Constants.ONE_TO_ONE_ORGANIZATION_TYPE && needsOne2OneAccountUpdate(c, oldContacts[i])) {
                            listContactNeedAccountUpdate.add(c);                            	
                        }
                        
                        // handle address changes for HH Accounts
                        if (c.npe01__Organization_Type__c == CAO_Constants.HH_ACCOUNT_TYPE && needsHHAccountAddressUpdate(c, oldContacts[i])) {
                            listContactNeedAccountUpdate.add(c);                               
                        }
                        
                    	// if the account (any type) has changed
                    	if (c.AccountId != oldContacts[i].AccountId) {
                    		
                            // need to update any HH Accounts, both rollups and naming
                            if (c.npe01__Organization_Type__c == CAO_Constants.HH_ACCOUNT_TYPE)
                                listAccountIdHHToUpdate.add(c.AccountId);
                            
                            // old account should be checked for deletion (if it wasn't private)
                            if (c.npe01__Private__c != true && oldContacts[i].npe01__Private__c != true)
                                listContactAccountDelete.add(oldContacts[i]);
                            
                            // old HH Accounts that don't get deleted still need to have name and rollups redone
                            if (oldContacts[i].npe01__Organization_Type__c == CAO_Constants.HH_ACCOUNT_TYPE)    
                                listAccountIdHHToUpdate.add(oldContacts[i].AccountId);
                                                   		                    	 
                    	   // HH Account didn't change, but it still might need renaming
                        } else if (c.npe01__Organization_Type__c == CAO_Constants.HH_ACCOUNT_TYPE && needsHHAccountRename(c, oldContacts[i])) {
                    	   listAccountIdHHToRename.add(c.AccountId);	
                    	}                    	
                    }
                    i += 1;
                }               
            }    

            // now done going thru all contacts, do our DML logic based on our lists
            
            if (listContactNeedAccount.size() > 0) {
                //add the newly created or updated Contacts that need a new individual account
                insertContactAccount(listContactNeedAccount);
            }
            if (listContactNeedBucketAccount.size() > 0) {
                //add the newly created or updated Contact to the bucket account
                attachToBucketAccount(listContactNeedBucketAccount);
            }
            if (listContactNeedAccountUpdate.size() > 0) {
                //contacts in the one-to-one model that are changing for syncing with account
                updateContactAccount(listContactNeedAccountUpdate);
            }
            if (mapAccountIdContactId.size() > 0) {
                //update Accounts that have newly created Contacts connected to them
                updateAccountPrimaryContact(mapAccountIdContactId);
                
                // update any HHAccount names
                updateExistingHHAccounts(contacts);                    
            }
            if (listAccountIdHHToUpdate.size() > 0) {
            	if (!system.isFuture()) {
                    RLLP_OppRollup.rollupAccountsFuture(new set<Id>(listAccountIdHHToUpdate));
            	} else {
		            RLLP_OppRollup rg = new RLLP_OppRollup();
		            map<id, Account> amap = new map<id, account>((list<Account>)Database.query(RLLP_OppRollup_UTIL.buildAccountQuery() + 
		                                                           ' where id IN :listAccountIdHHToUpdate')); 
		            rg.rollupAccounts(amap);		            
            	}    
            }
            if (listAccountIdHHToRename.size() > 0) {
                renameHHAccounts(listAccountIdHHToRename);    
            }
            if (listContactAccountDelete.size() > 0) {
                // check all old accounts to delete is they are left hanging around
                deleteContactAccountsIfEmpty(listContactAccountDelete);
            }
        }
    }

    /// <name> updateAccountPrimaryContact </name>
    /// <summary> Updates Accounts with the primary Individual Contact Id. Used for 1:1 and HH Accounts. </summary>
    /// <param name="accounts"> Map of account Ids, contact Ids </param>
    private void updateAccountPrimaryContact(Map<Id, Id> mapAccountIdContactId) {
        List<Account> listAccount = new List<Account>(); 
        for (Id i : mapAccountIdContactId.keySet()) {
            Account a = new Account(Id = i, npe01__One2OneContact__c = mapAccountIdContactId.get(i));
            listAccount.add(a);
        }
        if (listAccount.size() > 0) {
            Database.SaveResult[] lsr = Database.update(listAccount, false);
        }      
    }

    /// <name> updateExistingHHAccounts </name>
    /// <summary> for the list of contacts, rename their HH Accounts if they were added to an existing one.</summary>
    /// <param name="listContact">list of Contact records that are being updated</param>
    private void updateExistingHHAccounts(Contact[] listContact) {
        list<ID> listAccountIdHHRename = new list<ID>();
        
        // if the contact isn't the HH Account's primary contact, then this contact was added to an existing HH Account.
        for (Contact con : listContact) {
            if (con.AccountId != null && 
                con.Account.npe01__SYSTEM_AccountType__c == CAO_Constants.HH_ACCOUNT_TYPE &&
                con.Account.npe01__One2OneContact__c != null &&
                con.Account.npe01__One2OneContact__c != con.Id) {
                    // the account needs its name updated
                    listAccountIdHHRename.add(con.AccountId);
            }
        }
        
        renameHHAccounts(listAccountIdHHRename);
    }

    /// <name> renameHHAccounts </name>
    /// <summary> for the list of HH AccountId's, force their renaming </summary>
    /// <param name="listAccountId">list of Account Id</param>
    private void renameHHAccounts(ID[] listAccountId) {
    	if (listAccountId.size() == 1 || system.isFuture()) {
    	    HH_HouseholdNaming hhName = new HH_HouseholdNaming();
            hhName.UpdateNames(listAccountId);
    	} else {
            HH_HouseholdNaming.FutureUpdateNames(listAccountId);
    	}
    }

    /// <name> attachToBucketAccount </name>
    /// <summary> Updates Contacts to relate to a single Individual Account</summary>
    /// <param name="contacts"> Contacts meeting the trigger criteria</param>
    private void attachToBucketAccount(Contact[] contacts)
    {
        //grab the first Account that is named Individual
        List<Account> individuals = [Select Id from Account where name = :CAO_Constants.BUCKET_ACCOUNT_NAME ORDER BY CreatedDate Desc Limit 1];
        
        Id individualAccountId = CAO_Constants.GetIndividualAccountId();
        
        if (individuals.size() > 0)
        {
            for(Contact c : contacts)
            {
                //connect all Contacts to the bucket Account
                c.AccountId = individualAccountId;
            }
        } else
        {
            //if there is no bucket Account, the bucket model won't function unless we create one
            Account individual = new Account();
            individual.Name = CAO_Constants.BUCKET_ACCOUNT_NAME;
            //flag the account as an individual account
            individual.npe01__SYSTEMISINDIVIDUAL__c = true;
            //individual.Type = CAO_Constants.BUCKET_ORGANIZATION_TYPE;
            individual.npe01__SYSTEM_AccountType__c = CAO_Constants.BUCKET_ORGANIZATION_TYPE;
            insert individual;

            for(Contact c : contacts)
            {
                //connect Contact to bucket Account
                c.AccountId = individual.Id;
            }
        }
    }


    /// <name> insertContactAccount </name>
    /// <summary> Inserts a new 1:1 or HH Account for an Individual Contact</summary>
    /// <param name="contacts"> Contacts meeting the trigger criteria</param>
    private void insertContactAccount(Contact[] contacts)
    {
        List<Id> contactIds = new List<Id>();
        Map<Id,Id> conAccMap = new Map<Id,Id>();       
        
        for (Contact c : contacts) {
            //track which contacts are being inserted vs. updated
            if (c.Id != null) {
                contactIds.add(c.Id);
            }
        }
        // get all the Accounts that are connected to the existing Contacts
        for (Account acc : [Select Id, npe01__One2OneContact__c from Account where npe01__One2OneContact__c in :contactIds]) {
            conAccMap.put(acc.npe01__One2OneContact__c,acc.Id);
        }
        
        List<Contact> contactUpdates = new List<Contact>();
        List<Account> accountInserts = new List<Account>();

        Schema.Recordtypeinfo rtById = null;
        // check if recordtypes are enabled, and if it matches the existing setting
        // we go thru describe to validate that it is a valid recordType ID.
        ID rtId = CAO_Constants.isHHAccountModel() ? ContactsSettings.npe01__HH_Account_RecordTypeID__c : ContactsSettings.npe01__One_to_One_RecordTypeID__c;
        if (rtId != null) {
            Schema.DescribeSObjectResult R = Account.SObjectType.getDescribe();
            Map<Id,Schema.RecordTypeInfo> rtMapById = r.getRecordTypeInfosById();
            rtById = rtMapById.get(rtId);            
        }

        for (Contact c : contacts) {
            // if we found an Account already connected to this Contact, connect the Contact to that Account
            if (conAccMap.containsKey(c.Id)) {
                // if a user has blanked out the Account for a Contact, this will put it right back
                c.AccountId = conAccMap.get(c.Id);                
            } else {
                // construct the individul account for the Contact
                Account a = new Account();
                
                // construct the Account name
                a.Name = CAO_Constants.isHHAccountModel() ? strNameHHAccountForContact(c) : strNameOne2OneAccountForContact(c);
                
                //connect the Account to the Contact for 1:1 and HHAccount
                if (c.Id != null) {
                    a.npe01__One2OneContact__c = c.Id;
                }
                a.Phone = c.Phone;
                a.Fax = c.Fax;
                a.BillingStreet = c.MailingStreet;
                a.BillingCity = c.MailingCity;
                a.BillingState = c.MailingState;
                a.BillingPostalCode = c.MailingPostalCode;
                a.BillingCountry = c.MailingCountry;
                a.ShippingStreet = c.OtherStreet;
                a.ShippingCity = c.OtherCity;
                a.ShippingState = c.OtherState;
                a.ShippingCountry = c.OtherCountry;
                a.npe01__SYSTEM_AccountType__c = CAO_Constants.isHHAccountModel() ? CAO_Constants.HH_ACCOUNT_TYPE : CAO_Constants.ONE_TO_ONE_ORGANIZATION_TYPE;
                if (rtById != null) {                
                    a.put('RecordTypeID', rtByID.getRecordTypeID());
                }
                a.npe01__SYSTEMISINDIVIDUAL__c = true;
                accountInserts.add(a);
            }
        }
        
        if (accountInserts.size() > 0) {
            Database.SaveResult[] lsr = Database.insert(accountInserts, false);
            Integer i = 0;
            for (Contact c : contacts) {
                // for each success, write the new AccountId to the Contact. 
                if (lsr[i].isSuccess() == true) {
                    c.AccountId = lsr[i].getId();
                } else {
                    system.debug('Error inserting Accounts');
                    // DJH:UNDONE - need to use error class to log DML errors
                }
                i += 1;
            }
        }
    }


    /// <name> updateContactAccount </name>
    /// <summary> Updates an Individual Account for an Individual Contact</summary>
    /// <param name="contacts"> Contacts meeting the trigger criteria</param>
    private void updateContactAccount(Contact[] contacts)
    {
        Map<Id,Contact> accConMap = new Map<Id,Contact>();
        for (Contact c : contacts) {
            accConMap.put(c.AccountId, c);
        }
        //get the corresponding Accounts
        List<Account> accts = [Select a.npe01__SYSTEM_AccountType__c, a.name, a.ShippingStreet, a.ShippingState, a.ShippingPostalCode, a.ShippingCountry, 
	        a.ShippingCity, a.BillingStreet, a.BillingState, a.BillingPostalCode, a.BillingCountry, a.BillingCity
	        From Account a where a.Id IN :accConMap.keyset()];
        List<Account> listAccount = new List<Account>();
        
        for (Account a : accts) {         
            Contact c = accConMap.get(a.Id);
            //if any address data has changed on the contact, push it all to the Account
            /************* DJH: I've removed the difference check since the caller used needsOne2OneAccountUpdate() to see if an update was needed.
            if (
                c != null && (
                c.MailingStreet != a.BillingStreet ||
                c.MailingCity != a.BillingCity ||
                c.MailingState != a.BillingState ||
                c.MailingPostalCode != a.BillingPostalCode ||
                c.MailingCountry != a.BillingCountry ||
                c.OtherStreet != a.ShippingStreet ||
                c.OtherCity != a.ShippingCity ||
                c.OtherState != a.ShippingState ||
                c.OtherPostalCode != a.ShippingPostalCode ||
                c.OtherCountry != a.ShippingCountry ||
                EasternOrderLanguages.contains(OrgLanguage) ? c.LastName + ' ' + c.FirstName != a.Name : c.FirstName + ' ' + c.LastName != a.Name                               
                )
            ) 
            **************/
            {
                // Update Account fields
                a.BillingStreet = c.MailingStreet;
                a.BillingCity = c.MailingCity;
                a.BillingState = c.MailingState;
                a.BillingPostalCode = c.MailingPostalCode;
                a.BillingCountry = c.MailingCountry;
                a.ShippingStreet = c.OtherStreet;
                a.ShippingCity = c.OtherCity;
                a.ShippingState = c.OtherState;
                a.ShippingPostalCode = c.OtherPostalCode;
                a.ShippingCountry = c.OtherCountry;  
                if (a.npe01__SYSTEM_AccountType__c == CAO_Constants.ONE_TO_ONE_ORGANIZATION_TYPE)               
                    a.Name = strNameOne2OneAccountForContact(c);
                // HH Account naming updates handled seperately to deal with asyncronous naming

                listAccount.add(a);
            }           
        }   

        if (listAccount.size() > 0) {
            Database.SaveResult[] lsr = Database.update(listAccount, false);
            // DJH:UNDONE should handle DML errors and log them.
        }
    }
    
    //delete the accounts for contacts that have been deleted if they are empty (no ops, no hh members)
    public void deleteContactAccountsIfEmpty(Contact[] contacts) {
        List<Id> accountIds = new List<Id>();
        List<Account> accountsOnContacts = new List<Account>();
        List<Account> accountsForDeletion = new List<Account>();
        
        if (contacts.size() > 0) {
            for (Contact thisContact : contacts) {
                accountIds.add(thisContact.accountId);
            }

            accountsOnContacts = [Select Id, Type, npe01__SYSTEM_AccountType__c, (Select Id from Opportunities limit 1), (select Id from Contacts limit 1) from Account where Id IN :accountIds];
            
            for (Account thisAccount : accountsOnContacts) {
                //if the legacy or current type field show it's not a one-to-one or HH Account record, don't delete the account
                if (thisAccount.Type == CAO_Constants.ONE_TO_ONE_ORGANIZATION_TYPE || 
                    thisAccount.npe01__SYSTEM_AccountType__c == CAO_Constants.ONE_TO_ONE_ORGANIZATION_TYPE ||
                    thisAccount.npe01__SYSTEM_AccountType__c == CAO_Constants.HH_ACCOUNT_TYPE) {
                    
                    // if there are no Opportunities for this Account, add it for deletion
                    if (thisAccount.Opportunities.size() == 0 && thisAccount.Contacts.size() == 0) {
                        accountsForDeletion.add(thisAccount);
                    }
                }   
            }        
        }
        // delete the accounts
        if (accountsForDeletion.size() > 0) {           
            delete accountsForDeletion;
        }        
    }

    // returns whether changes in the contact require an update to the 1:1 account   
    private boolean needsOne2OneAccountUpdate(Contact conNew, Contact conOld) {
       return (conNew.AccountId != conOld.AccountId ||
                conNew.FirstName != conOld.FirstName ||
	            conNew.LastName != conOld.LastName ||
	            conNew.MailingStreet != conOld.MailingStreet ||
	            conNew.MailingCity != conOld.MailingCity ||
	            conNew.MailingState != conOld.MailingState ||
	            conNew.MailingPostalCode != conOld.MailingPostalCode ||
	            conNew.MailingCountry != conOld.MailingCountry ||
	            conNew.OtherStreet != conOld.OtherStreet ||
	            conNew.OtherCity != conOld.OtherCity ||
	            conNew.OtherState != conOld.OtherState ||
	            conNew.OtherPostalCode != conOld.OtherPostalCode ||
	            conNew.OtherCountry != conOld.OtherCountry ||
	            conNew.Phone != conOld.Phone ||
	            conNew.Fax != conOld.Fax);
    }
 
    // returns whether changes in the contact require a rename of a HH Account   
    private boolean needsHHAccountRename(Contact conNew, Contact conOld) {
        return (conNew.Firstname != conOld.Firstname ||
                conNew.Lastname != conOld.Lastname ||
                conNew.Salutation != conOld.Salutation ||
                conNew.npo02__Naming_Exclusions__c != conOld.npo02__Naming_Exclusions__c);
    }   
    
    // returns whether changes in the contact require an address change in the HH Account
    private boolean needsHHAccountAddressUpdate(Contact conNew, Contact conOld) {
       return ( conNew.MailingStreet != conOld.MailingStreet ||
                conNew.MailingCity != conOld.MailingCity ||
                conNew.MailingState != conOld.MailingState ||
                conNew.MailingPostalCode != conOld.MailingPostalCode ||
                conNew.MailingCountry != conOld.MailingCountry ||
                conNew.OtherStreet != conOld.OtherStreet ||
                conNew.OtherCity != conOld.OtherCity ||
                conNew.OtherState != conOld.OtherState ||
                conNew.OtherPostalCode != conOld.OtherPostalCode ||
                conNew.OtherCountry != conOld.OtherCountry);
    }

    // the default name for a new HH Account
    public static String strNameHHAccountForContact(Contact con) {
        return con.LastName + ' ' + system.label.npo02.DefaultHouseholdName;
    }

    // the default name for a new 1:1 Account
    public static String strNameOne2OneAccountForContact(Contact con) {
        String str = '';
        
        if (con.FirstName != null) {
            str += con.FirstName;
            str += ' ' ;
        }                
        if (EasternOrderLanguages.contains(OrgLanguage))
            str = con.LastName + ' ' + str;
        else
            str += con.LastName;
        
        return str;
    }

}