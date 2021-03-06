/*
 * CPUserDefaults.j
 * Foundation
 *
 * Created by Nicholas Small.
 * Copyright 2010, 280 North, Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

@import "CPObject.j"


CPArgumentDomain = @"CPArgumentDomain";
CPApplicationDomain = [[[CPBundle mainBundle] infoDictionary] objectForKey:@"CPBundleIdentifier"] || @"CPApplicationDomain";
CPGlobalDomain = @"CPGlobalDomain";
CPLocaleDomain = @"CPLocaleDomain";
CPRegistrationDomain = @"CPRegistrationDomain";

CPUserDefaultsDidChangeNotification = @"CPUserDefaultsDidChangeNotification";

var StandardUserDefaults;

/*!
    @ingroup foundation
    @class CPUserDefaults

    CPUserDefaults provides a way of storing a list of user preferences. Everything you store must be CPCoding compliant because it is stored as CPData.

    Unlike in Cocoa, CPUserDefaults is per-host by default because of the method of storage. By default, the localStorage API will be used if the browser
    supports it. Otherwise a cookie fallback mechanism is utilized. Be aware that if the user erases the local database or clears their cookies, all the
    preferences will be lost. Also be aware that this is not a safe storage method; do not store sensitive data in the defaults database.

    The storage method utilized is determined by matching the writing domain to a dictionary of stores, concrete subclasses of the CPUserDefaultsStore abstract
    class. This is a deviation from Cocoa. You can create a custom defaults store by subclassing the abstract class and implementing the protocol. Currently the
    protocol consists of only two methods: -data and -setData:. The latter needs to store the passed in CPData object in your storage mechanism and the former
    needs to return an equivalent CPData object synchronously. You can then configure CPUserDefaults to use your storage mechanism using
    -setPersistentStoreClass:forDomain:reloadData:
*/
@implementation CPUserDefaults : CPObject
{
    CPDictionary            _domains;
    CPDictionary            _stores;

    CPDictionary            _searchList;
    BOOL                    _searchListNeedsReload;
}

/*!
    Returns the shared defaults object.
*/
+ (id)standardUserDefaults
{
    if (!StandardUserDefaults)
        StandardUserDefaults = [[CPUserDefaults alloc] init];

    return StandardUserDefaults;
}

/*!
    Synchronizes any changes made to the shared user defaults object and releases it from memory.
    A subsequent invocation of standardUserDefaults creates a new shared user defaults object with the standard search list.
*/
+ (void)resetStandardUserDefaults
{
    if (StandardUserDefaults)
        [StandardUserDefaults synchronize];

    StandardUserDefaults = nil;
}

/*
    @ignore
*/
- (id)init
{
    self = [super init];

    if (self)
    {
        _domains = [CPDictionary dictionary];
        [self _setupArgumentsDomain];

        var defaultStore = [CPUserDefaultsLocalStore supportsLocalStorage] ? CPUserDefaultsLocalStore : CPUserDefaultsCookieStore;

        _stores = [CPDictionary dictionary];
        [self setPersistentStoreClass:defaultStore forDomain:CPGlobalDomain reloadData:YES];
        [self setPersistentStoreClass:defaultStore forDomain:CPApplicationDomain reloadData:YES];
    }

    return self;
}

/*
    @ignore
*/
- (void)_setupArgumentsDomain
{
    var args = [CPApp namedArguments],
        keys = [args allKeys],
        count = [keys count];

    for (var i = 0; i < count; i++)
    {
        var key = keys[i];
        [self setObject:[args objectForKey:key] forKey:key inDomain:CPArgumentDomain];
    }
}

/*!
    Return a default value. The order of domains in the search list is: CPRegistrationDomain, CPGlobalDomain, CPApplicationDomain, CPArgumentDomain.
    Calling this method may cause the search list to be recreated if any new values have recently been set. Be aware of the performance ramifications.
*/
- (id)objectForKey:(CPString)aKey
{
    if (_searchListNeedsReload)
        [self _reloadSearchList];

    return [_searchList objectForKey:aKey];
}

/*!
    Set a default value in your application domain.
*/
- (void)setObject:(id)anObject forKey:(CPString)aKey
{
    [self setObject:anObject forKey:aKey inDomain:CPApplicationDomain];
}

/*!
    Return a default value from a specific domain. If you know
    which domain you'd like to use you should always use this method
    because it doesn't have to hit the search list.
*/
- (id)objectForKey:(CPString)aKey inDomain:(CPString)aDomain
{
    var domain = [_domains objectForKey:aDomain];

    if (!domain)
        return nil;

    return [domain objectForKey:aKey];
}

/*!
    Set a default value in the domain you pass in. If the domain is CPApplicationDomain or CPGlobalDomain,
    the defaults store will eventually be persisted. You can call -forceFlush to force a persist.
*/
- (void)setObject:(id)anObject forKey:(CPString)aKey inDomain:(CPString)aDomain
{
    if (!aKey || !aDomain)
        return;

    var domain = [_domains objectForKey:aDomain];
    if (!domain)
    {
        domain = [CPDictionary dictionary];
        [_domains setObject:domain forKey:aDomain];
    }

    [domain setObject:anObject forKey:aKey];
    [self domainDidChange:aDomain];

    _searchListNeedsReload = YES;
}

/*!
    Removes the value of the specified default key in the standard application domain.
    Removing a default has no effect on the value returned by the objectForKey: method if the same key exists in a domain that precedes the standard application domain in the search list.
*/
- (void)removeObjectForKey:(CPString)aKey
{
    [self removeObjectForKey:aKey inDomain:CPApplicationDomain];
}

/*!
    Removes the value of the specified default key in the specified domain.
*/
- (void)removeObjectForKey:(CPString)aKey inDomain:(CPString)aDomain
{
    if (!aKey || !aDomain)
        return;

    var domain = [_domains objectForKey:aDomain];
    if (!domain)
        return;

    [domain removeObjectForKey:aKey];
    [self domainDidChange:aDomain];

    _searchListNeedsReload = YES;
}

/*!
    Adds the contents the specified dictionary to the registration domain.

    If there is no registration domain, one is created using the specified dictionary, and CPRegistrationDomain is added to the end of the search list.
    The contents of the registration domain are not written to disk; you need to call this method each time your application starts. You can place a plist file in the application's Resources directory and call registerDefaultsWithContentsOfFile:

    @param aDictionary The dictionary of keys and values you want to register.
*/
- (void)registerDefaults:(CPDictionary)aDictionary
{
    var keys = [aDictionary allKeys],
        count = [keys count];

    for (var i = 0; i < count; i++)
    {
        var key = keys[i];
        [self setObject:[aDictionary objectForKey:key] forKey:key inDomain:CPRegistrationDomain];
    }
}

/*!
    This is just a convenience method to load a plist resource and register all the values it contains as defaults.

    NOTE: This sends a synchronous request. If you don't want to do that, create a dictionary any way you want (including loading a plist)
    and pass it to -registerDefaults:
*/
- (void)registerDefaultsFromContentsOfFile:(CPURL)aURL
{
    var contents = [CPURLConnection sendSynchronousRequest:[CPURLRequest requestWithURL:aURL] returningResponse:nil error:nil],
        data = [CPData dataWithRawString:[contents string]],
        plist = [data plistObject];

    [self registerDefaults:plist];
}

/*
    @ignore
*/
- (void)_reloadSearchList
{
    _searchListNeedsReload = NO;

    var dicts = [CPRegistrationDomain, CPGlobalDomain, CPApplicationDomain, CPArgumentDomain],
        count = [dicts count];

    _searchList = [CPDictionary dictionary];

    for (var i = 0; i < count; i++)
    {
        var domain = [_domains objectForKey:dicts[i]];
        if (!domain)
            continue;

        var keys = [domain allKeys],
            keysCount = [keys count];

        for (var j = 0; j < keysCount; j++)
        {
            var key = keys[j];
            [_searchList setObject:[domain objectForKey:key] forKey:key];
        }
    }
}

// Synchronization

/*!
    Returns an array of currently volatile domain names.
*/
- (CPArray)volatileDomainNames
{
    return [CPArgumentDomain, CPLocaleDomain, CPRegistrationDomain];
}

/*!
    Returns an array of currently persistent domain names.
*/
- (CPArray)persistentDomainNames
{
    return [CPGlobalDomain, CPApplicationDomain];
}

/*!
    Returns the currently used instance of CPUserDefaultStore concrete subclass for the given domain name.
*/
- (CPUserDefaultsStore)persistentStoreForDomain:(CPString)aDomain
{
    return [_stores objectForKey:aDomain];
}

/*!
    Set the CPUserDefaultStore concrete subclass that should be instantiated for use
    in persisting the given domain name.

    @param aStoreClass The concrete subclass of CPUserDefaultsStore to use to store the defaults database for this domain
    @param aDomain The name of the domain for which you want to change the storage mechanism
    @param reloadData Empty the cached defaults for this domain and reload them from the new storage mechanism
*/
- (CPUserDefaultsStore)setPersistentStoreClass:(Class)aStoreClass forDomain:(CPString)aDomain reloadData:(BOOL)aFlag
{
    var currentStore = [_stores objectForKey:aDomain];
    if (currentStore && [currentStore class] === aStoreClass)
        return currentStore;

    var store = [[aStoreClass alloc] init];
    [store setDomain:aDomain];
    [_stores setObject:store forKey:aDomain];

    if (aFlag)
        [self reloadDataFromStoreForDomain:aDomain];

    return store;
}

/*!
    @ignore
*/
- (void)reloadDataFromStoreForDomain:(CPString)aDomain
{
    var data = [[self persistentStoreForDomain:aDomain] data],
        domain = data ? [CPKeyedUnarchiver unarchiveObjectWithData:data] : nil;

    [_domains setObject:domain forKey:aDomain];

    _searchListNeedsReload = YES;
}

/*!
    @ignore
*/
- (void)domainDidChange:(CPString)aDomain
{
    if (aDomain === CPGlobalDomain || aDomain === CPApplicationDomain)
        [[CPRunLoop currentRunLoop] performSelector:@selector(synchronize) target:self argument:nil order:0 modes:[CPDefaultRunLoopMode]];

    [[CPNotificationCenter defaultCenter] postNotificationName:CPUserDefaultsDidChangeNotification object:self];
}

/*!
    Force write out of defaults database immediately.
*/
- (void)synchronize
{
    var globalDomain = [_domains objectForKey:CPGlobalDomain];
    if (globalDomain)
    {
        var data = [CPKeyedArchiver archivedDataWithRootObject:globalDomain];
        [[self persistentStoreForDomain:CPGlobalDomain] setData:data];
    }

    var appDomain = [_domains objectForKey:CPApplicationDomain];
    if (appDomain)
    {
        var data = [CPKeyedArchiver archivedDataWithRootObject:appDomain];
        [[self persistentStoreForDomain:CPApplicationDomain] setData:data];
    }
}

// Value accessors

/*!
    Returns the Boolean value associated with the specified key.
*/
- (BOOL)boolForKey:(CPString)aKey
{
    var value = [self objectForKey:aKey];
    if ([value respondsToSelector:@selector(boolValue)])
        return [value boolValue]

    return value;
}

/*!
    Returns the floating-point value associated with the specified key.
*/
- (float)floatForKey:(CPString)aKey
{
    var value = [self objectForKey:aKey];
    if ([value respondsToSelector:@selector(floatValue)])
        return [value floatValue];

    return value;
}

/*!
    Returns the double value associated with the specified key.
*/
- (double)doubleForKey:(CPString)aKey
{
    var value = [self objectForKey:aKey];
    if ([value respondsToSelector:@selector(doubleValue)])
        return [value doubleValue];

    return value;
}

/*!
    Returns the integer value associated with the specified key.
*/
- (int)integerForKey:(CPString)aKey
{
    var value = [self objectForKey:aKey];
    if ([value respondsToSelector:@selector(intValue)])
        return [value intValue];

    return value;
}

@end

@implementation CPUserDefaultsStore : CPObject
{
    CPString    domain  @accessors;
}

- (CPData)data
{
    _CPRaiseInvalidAbstractInvocation(self, _cmd);
    return nil;
}

- (void)setData:(CPData)aData
{
    _CPRaiseInvalidAbstractInvocation(self, _cmd);
}

@end

@implementation CPUserDefaultsCookieStore : CPUserDefaultsStore
{
    CPCookie    _cookie;
}

- (void)setDomain:(CPString)aDomain
{
    if (domain === aDomain)
        return;

    domain = aDomain;

    _cookie = [[CPCookie alloc] initWithName:domain];
}

- (CPData)data
{
    var result = [_cookie value];
    if (!result || [result length] < 1)
        return nil;

    return [CPData dataWithRawString:decodeURIComponent(result)];
}

- (void)setData:(CPData)aData
{
    [_cookie setValue:encodeURIComponent([aData rawString]) expires:[CPDate distantFuture] domain:window.location.href.hostname];
}

@end

@implementation CPUserDefaultsLocalStore : CPUserDefaultsStore
{
}

+ (BOOL)supportsLocalStorage
{
    return !!window.localStorage;
}

- (id)init
{
    if (![[self class] supportsLocalStorage])
    {
        [CPException raise:@"UnsupportedFeature" reason:@"Browser does not support localStorage for CPUserDefaultsLocalStore"];
        return self = nil;
    }

    return self = [super init];
}

- (CPData)data
{
    var result = localStorage.getItem(domain);
    if (!result || [result length] < 1)
        return nil;

    return [CPData dataWithRawString:decodeURIComponent(result)];
}

- (void)setData:(CPData)aData
{
    localStorage.setItem(domain, encodeURIComponent([aData rawString]));
}

@end
